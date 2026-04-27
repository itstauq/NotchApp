const DEFAULT_MAX_ROWS = 20;
const DEFAULT_TIMEOUT_MS = 30000;
const LOGOUT_TIMEOUT_MS = 1000;
const decoder = new TextDecoder();

function normalizeText(value) {
  return typeof value === "string" ? value.trim() : "";
}

export function parsePort(value, fallback = 993) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  return Number.isFinite(parsed) && parsed > 0 && parsed <= 65535 ? parsed : fallback;
}

export function parseMaxRows(value, fallback = DEFAULT_MAX_ROWS) {
  const parsed = Number.parseInt(String(value ?? ""), 10);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.max(1, Math.min(parsed, 50));
}

function quoteIMAPString(value) {
  return `"${String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
}

function tagFactory() {
  let nextTag = 0;
  return () => `A${String(++nextTag).padStart(4, "0")}`;
}

function delay(ms) {
  return new Promise((resolve) => {
    setTimeout(resolve, ms);
  });
}

function taggedStatus(response, tag) {
  const line = response
    .split(/\r?\n/)
    .find((candidate) => candidate.startsWith(`${tag} `));
  const status = line?.split(/\s+/)[1]?.toUpperCase();
  return { line, status };
}

async function readChunk(socket, signal) {
  const chunk = await socket.read({ maxBytes: 65536, timeoutMs: DEFAULT_TIMEOUT_MS, signal });
  if (chunk == null) {
    return null;
  }
  return decoder.decode(chunk, { stream: true });
}

async function createIMAPSession(options) {
  const socket = await options.connect({
    host: options.host,
    port: options.port,
    serverName: options.host,
    timeoutMs: DEFAULT_TIMEOUT_MS,
  });
  const nextTag = tagFactory();
  let buffer = "";

  async function ensureBuffered(signal) {
    if (buffer.length > 0) {
      return true;
    }
    const chunk = await readChunk(socket, signal);
    if (chunk == null) {
      return false;
    }
    buffer += chunk;
    return true;
  }

  async function readLine(signal) {
    while (true) {
      const newlineIndex = buffer.indexOf("\r\n");
      if (newlineIndex >= 0) {
        const line = buffer.slice(0, newlineIndex);
        buffer = buffer.slice(newlineIndex + 2);
        return line;
      }

      const hasMore = await ensureBuffered(signal);
      if (!hasMore) {
        if (buffer.length === 0) {
          return null;
        }

        const line = buffer;
        buffer = "";
        return line;
      }
    }
  }

  async function readLiteral(byteCount, signal) {
    while (buffer.length < byteCount) {
      const chunk = await readChunk(socket, signal);
      if (chunk == null) {
        break;
      }
      buffer += chunk;
    }

    const literal = buffer.slice(0, byteCount);
    buffer = buffer.slice(byteCount);
    return literal;
  }

  async function readResponse(tag, signal) {
    let response = "";
    while (true) {
      const line = await readLine(signal);
      if (line == null) {
        throw new Error(`IMAP connection closed before ${tag} completed.`);
      }

      response += `${line}\r\n`;

      const literalMatch = line.match(/\{(\d+)\}$/);
      if (literalMatch) {
        response += await readLiteral(Number.parseInt(literalMatch[1], 10), signal);
      }

      if (line.startsWith(`${tag} `)) {
        return response;
      }
    }
  }

  async function command(commandText, signal) {
    const tag = nextTag();
    await socket.write(`${tag} ${commandText}\r\n`);
    const response = await readResponse(tag, signal);
    const { status, line } = taggedStatus(response, tag);
    if (status !== "OK") {
      throw new Error(line || `IMAP command failed: ${commandText}`);
    }
    return response;
  }

  await readLine(options.signal);

  return {
    command,
    async close() {
      const logout = socket.write(`${nextTag()} LOGOUT\r\n`).catch(() => {});
      await Promise.race([logout, delay(LOGOUT_TIMEOUT_MS)]);
      await socket.close();
    },
  };
}

export function parseSearchResponse(response) {
  const line = response
    .split(/\r?\n/)
    .find((candidate) => candidate.toUpperCase().startsWith("* SEARCH"));
  if (!line) {
    return [];
  }

  return line
    .replace(/^\* SEARCH\s*/i, "")
    .trim()
    .split(/\s+/)
    .filter(Boolean);
}

function unfoldHeader(value) {
  return value.replace(/\r?\n[ \t]+/g, " ").trim();
}

function decodeMimeWords(value) {
  return value.replace(/=\?([^?]+)\?([bqBQ])\?([^?]+)\?=/g, (_match, charset, encoding, body) => {
    try {
      const normalizedCharset = String(charset).toLowerCase();
      if (normalizedCharset !== "utf-8" && normalizedCharset !== "us-ascii") {
        return body;
      }

      const bytes = encoding.toLowerCase() === "b"
        ? Uint8Array.from(atob(body), (char) => char.charCodeAt(0))
        : new TextEncoder().encode(body.replace(/_/g, " ").replace(/=([0-9A-F]{2})/gi, (_hex, value) => {
            return String.fromCharCode(Number.parseInt(value, 16));
          }));
      return new TextDecoder(normalizedCharset).decode(bytes);
    } catch {
      return body;
    }
  });
}

function headerValue(headers, name) {
  const match = headers.match(new RegExp(`^${name}:([\\s\\S]*?)(?=\\r?\\n[^ \\t]|\\r?\\n\\r?\\n|$)`, "im"));
  return match ? decodeMimeWords(unfoldHeader(match[1])) : "";
}

function senderName(from) {
  const trimmed = from.trim();
  if (!trimmed) {
    return "Unknown";
  }

  const angleIndex = trimmed.indexOf("<");
  const display = angleIndex > 0 ? trimmed.slice(0, angleIndex).trim() : trimmed;
  return display.replace(/^"|"$/g, "").trim() || trimmed.replace(/[<>]/g, "");
}

export function parseFetchResponse(response) {
  const messages = [];
  const pattern = /\*\s+(\d+)\s+FETCH[\s\S]*?\{(\d+)\}\r?\n([\s\S]*?)(?=\r?\n\)|\r?\n\*\s+\d+\s+FETCH|$)/gi;
  let match;

  while ((match = pattern.exec(response)) !== null) {
    const sequence = match[1];
    const fetchPrefix = match[0].slice(0, Math.max(0, match[0].indexOf("{")));
    const uid = fetchPrefix.match(/\bUID\s+(\d+)\b/i)?.[1] ?? sequence;
    const headers = match[3] ?? "";
    const sender = senderName(headerValue(headers, "From"));
    const subject = headerValue(headers, "Subject") || "(No subject)";
    const avatar = sender.slice(0, 1).toUpperCase() || "?";

    messages.push({
      id: `imap-${uid}`,
      uid,
      sender,
      subject,
      avatar,
      tint: "#FA757A",
      unread: true,
    });
  }

  return messages.reverse();
}

function decodeTransferText(value) {
  return value
    .replace(/=\r?\n/g, "")
    .replace(/=([0-9A-F]{2})/gi, (_match, hex) => {
      return String.fromCharCode(Number.parseInt(hex, 16));
    });
}

function stripHTML(value) {
  return value
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<br\s*\/?>/gi, "\n")
    .replace(/<\/p>/gi, "\n\n")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'");
}

function stripMIMEPartHeaders(value) {
  const normalized = value.replace(/\r\n/g, "\n");
  const separatorIndex = normalized.indexOf("\n\n");
  if (separatorIndex < 0) {
    return value;
  }

  const headerBlock = normalized.slice(0, separatorIndex);
  const hasMIMEHeaders = /^(Content-Type|Content-Transfer-Encoding|Content-Disposition|MIME-Version):/im
    .test(headerBlock);
  return hasMIMEHeaders ? normalized.slice(separatorIndex + 2) : normalized;
}

function mimeHeaderBlock(value) {
  const normalized = value.replace(/\r\n/g, "\n");
  const separatorIndex = normalized.indexOf("\n\n");
  if (separatorIndex < 0) {
    return { headers: "", body: value };
  }

  return {
    headers: normalized.slice(0, separatorIndex),
    body: normalized.slice(separatorIndex + 2),
  };
}

function isAttachmentPart(headers) {
  const normalized = headers.replace(/\r?\n[ \t]+/g, " ").toLowerCase();
  const contentType = normalized.match(/^content-type:\s*([^\s;]+)/im)?.[1] ?? "";
  const disposition = normalized.match(/^content-disposition:\s*([^\s;]+)/im)?.[1] ?? "";

  if (disposition === "attachment" || /\bfilename\*=|\bfilename=/i.test(normalized)) {
    return true;
  }

  if (/\bname\*=|\bname=/i.test(normalized) && !contentType.startsWith("text/")) {
    return true;
  }

  return Boolean(contentType) && contentType !== "text/plain" && contentType !== "text/html";
}

function stripAttachmentMIMEParts(value) {
  const normalized = value.replace(/\r\n/g, "\n");
  if (!/^--[^\s-][^\n]*$/m.test(normalized)) {
    return value;
  }

  const keptParts = [];
  const boundaryPattern = /^--[^\s-][^\n]*(?:--)?$/gm;
  let previousBoundaryEnd = null;
  let match;

  while ((match = boundaryPattern.exec(normalized)) !== null) {
    if (previousBoundaryEnd != null) {
      const part = normalized.slice(previousBoundaryEnd, match.index).replace(/^\n|\n$/g, "");
      const { headers, body } = mimeHeaderBlock(part);
      if (!isAttachmentPart(headers)) {
        keptParts.push(body.trim());
      }
    }

    previousBoundaryEnd = match.index + match[0].length;
  }

  if (keptParts.length === 0) {
    return value;
  }

  return keptParts.filter(Boolean).join("\n\n");
}

function wrapLongTokens(value) {
  return value.replace(/\S{32,}/g, (token) => {
    return token.match(/.{1,24}/g)?.join(" ") ?? token;
  });
}

function normalizeBodyPreview(value) {
  const decoded = decodeTransferText(stripMIMEPartHeaders(stripAttachmentMIMEParts(value)));
  const text = /<\/?[a-z][\s\S]*>/i.test(decoded) ? stripHTML(decoded) : decoded;
  return wrapLongTokens(text)
    .replace(/\r\n/g, "\n")
    .replace(/[ \t]{2,}/g, " ")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

export function parseMessageDetailResponse(response) {
  const literalMatch = response.match(/\{(\d+)\}\r?\n/i);
  if (!literalMatch || literalMatch.index == null) {
    return { body: "" };
  }

  const byteCount = Number.parseInt(literalMatch[1], 10);
  const literalStart = literalMatch.index + literalMatch[0].length;
  const literal = response.slice(literalStart, literalStart + byteCount);
  return {
    body: normalizeBodyPreview(literal),
  };
}

function createSessionOptions(options) {
  return {
    connect: options.connect,
    host: normalizeText(options.host),
    port: parsePort(options.port),
    signal: options.signal,
  };
}

export async function fetchUnreadIMAPMessages(options) {
  const host = normalizeText(options.host);
  const email = normalizeText(options.email);
  const password = normalizeText(options.password);
  const mailbox = normalizeText(options.mailbox) || "INBOX";
  const maxRows = parseMaxRows(options.maxRows);

  if (!host || !email || !password) {
    return { messages: [], unreadCount: 0, needsConfiguration: true };
  }

  const session = await createIMAPSession({
    ...createSessionOptions(options),
    host,
  });

  try {
    await session.command(`LOGIN ${quoteIMAPString(email)} ${quoteIMAPString(password)}`, options.signal);
    await session.command(`SELECT ${quoteIMAPString(mailbox)}`, options.signal);
    const searchResponse = await session.command("UID SEARCH UNSEEN", options.signal);
    const unreadIDs = parseSearchResponse(searchResponse);
    if (unreadIDs.length === 0) {
      return { messages: [], unreadCount: 0, needsConfiguration: false };
    }

    const fetchIDs = unreadIDs.slice(-maxRows).join(",");
    const fetchResponse = await session.command(
      `UID FETCH ${fetchIDs} (UID BODY.PEEK[HEADER.FIELDS (FROM SUBJECT)])`,
      options.signal
    );

    return {
      messages: parseFetchResponse(fetchResponse),
      unreadCount: unreadIDs.length,
      needsConfiguration: false,
    };
  } finally {
    await session.close();
  }
}

export async function fetchIMAPMessageDetail(options) {
  const host = normalizeText(options.host);
  const email = normalizeText(options.email);
  const password = normalizeText(options.password);
  const mailbox = normalizeText(options.mailbox) || "INBOX";
  const uid = normalizeText(options.uid);

  if (!host || !email || !password || !uid) {
    return null;
  }

  const session = await createIMAPSession({
    ...createSessionOptions(options),
    host,
  });

  try {
    await session.command(`LOGIN ${quoteIMAPString(email)} ${quoteIMAPString(password)}`, options.signal);
    await session.command(`SELECT ${quoteIMAPString(mailbox)}`, options.signal);
    const response = await session.command(
      `UID FETCH ${uid} (BODY.PEEK[TEXT])`,
      options.signal
    );
    return parseMessageDetailResponse(response);
  } finally {
    await session.close();
  }
}

export async function markIMAPMessageRead(options) {
  const host = normalizeText(options.host);
  const email = normalizeText(options.email);
  const password = normalizeText(options.password);
  const mailbox = normalizeText(options.mailbox) || "INBOX";
  const uid = normalizeText(options.uid);

  if (!host || !email || !password || !uid) {
    return false;
  }

  const session = await createIMAPSession({
    ...createSessionOptions(options),
    host,
  });

  try {
    await session.command(`LOGIN ${quoteIMAPString(email)} ${quoteIMAPString(password)}`, options.signal);
    await session.command(`SELECT ${quoteIMAPString(mailbox)}`, options.signal);
    await session.command(`UID STORE ${uid} +FLAGS.SILENT (\\Seen)`, options.signal);
    return true;
  } finally {
    await session.close();
  }
}
