const { callRpc } = require("../runtime");

function createConnectionId() {
  return `tcp:${globalThis.crypto.randomUUID()}`;
}

function createRequestId() {
  return `tcp-read:${globalThis.crypto.randomUUID()}`;
}

function encodeBody(body) {
  if (typeof body === "string") {
    return Buffer.from(body, "utf8").toString("base64");
  }

  if (body instanceof ArrayBuffer) {
    return Buffer.from(body).toString("base64");
  }

  if (ArrayBuffer.isView(body)) {
    return Buffer.from(body.buffer, body.byteOffset, body.byteLength).toString("base64");
  }

  throw new TypeError("TCP write body must be a string, Uint8Array, or ArrayBuffer.");
}

function decodeBody(payload) {
  if (payload == null) {
    return null;
  }

  if (payload.bodyEncoding !== "base64") {
    throw new Error("Unsupported TCP read body encoding.");
  }

  return new Uint8Array(Buffer.from(payload.body ?? "", "base64"));
}

function createAbortError() {
  return new DOMException("The operation was aborted.", "AbortError");
}

async function connectTCP(options = {}) {
  const {
    host,
    port,
    serverName,
    timeoutMs,
  } = options;
  const connectionId = createConnectionId();
  let closed = false;

  await callRpc("network.tcp.connect", {
    connectionId,
    host,
    port,
    serverName,
    timeoutMs,
  });

  return {
    connectionId,

    async write(body) {
      if (closed) {
        throw new Error("TCP socket is closed.");
      }

      await callRpc("network.tcp.write", {
        connectionId,
        body: encodeBody(body),
        bodyEncoding: "base64",
      });
    },

    async read(options = {}) {
      if (closed) {
        return null;
      }

      const requestId = createRequestId();
      const signal = options.signal;

      if (signal?.aborted) {
        throw createAbortError();
      }

      let abortListener = null;
      const rpcPromise = callRpc("network.tcp.read", {
        connectionId,
        requestId,
        maxBytes: options.maxBytes,
        timeoutMs: options.timeoutMs,
      });
      const abortPromise = signal
        ? new Promise((_, reject) => {
            abortListener = () => {
              Promise.resolve(callRpc("request.cancel", { requestId })).catch(() => {});
              reject(createAbortError());
            };
            signal.addEventListener("abort", abortListener, { once: true });
          })
        : null;

      try {
        const result = await (abortPromise ? Promise.race([rpcPromise, abortPromise]) : rpcPromise);
        return decodeBody(result);
      } finally {
        if (abortListener) {
          signal?.removeEventListener("abort", abortListener);
        }
      }
    },

    async close() {
      if (closed) {
        return;
      }

      closed = true;
      await callRpc("network.tcp.close", { connectionId });
    },
  };
}

module.exports = {
  connectTCP,
};
