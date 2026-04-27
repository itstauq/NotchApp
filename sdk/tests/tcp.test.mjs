import assert from "node:assert/strict";
import { createRequire } from "node:module";
import { test } from "node:test";

const require = createRequire(import.meta.url);
const { connectTCP } = require("../packages/api/functions/tcp");

test("connectTCP exposes stream-like read write and close helpers", async () => {
  const calls = [];
  globalThis.__SKYLANE_RUNTIME__ = {
    callRpc(method, params) {
      calls.push({ method, params });
      if (method === "network.tcp.read") {
        return Promise.resolve({
          body: Buffer.from("OK").toString("base64"),
          bodyEncoding: "base64",
        });
      }
      return Promise.resolve(null);
    },
  };

  const socket = await connectTCP({
    host: "imap.example.com",
    port: 993,
    timeoutMs: 1000,
  });
  await socket.write("A1 NOOP\r\n");
  const chunk = await socket.read({ maxBytes: 32, timeoutMs: 1000 });
  await socket.close();
  await socket.close();

  assert.deepEqual(
    calls.map((call) => call.method),
    [
      "network.tcp.connect",
      "network.tcp.write",
      "network.tcp.read",
      "network.tcp.close",
    ]
  );
  assert.equal(calls[0].params.host, "imap.example.com");
  assert.equal(calls[0].params.port, 993);
  assert.equal(calls[1].params.body, Buffer.from("A1 NOOP\r\n").toString("base64"));
  assert.equal(calls[1].params.bodyEncoding, "base64");
  assert.equal(calls[2].params.maxBytes, 32);
  assert.equal(new TextDecoder().decode(chunk), "OK");

  delete globalThis.__SKYLANE_RUNTIME__;
});

test("connectTCP read returns null on clean EOF", async () => {
  globalThis.__SKYLANE_RUNTIME__ = {
    callRpc(method) {
      return Promise.resolve(method === "network.tcp.read" ? null : {});
    },
  };

  const socket = await connectTCP({ host: "imap.example.com", port: 993 });
  assert.equal(await socket.read(), null);

  delete globalThis.__SKYLANE_RUNTIME__;
});

test("connectTCP read cancellation sends request.cancel", async () => {
  const calls = [];
  globalThis.__SKYLANE_RUNTIME__ = {
    callRpc(method, params) {
      calls.push({ method, params });
      if (method === "network.tcp.read") {
        return new Promise(() => {});
      }
      return Promise.resolve(null);
    },
  };

  const socket = await connectTCP({ host: "imap.example.com", port: 993 });
  const controller = new AbortController();
  const readPromise = socket.read({ signal: controller.signal });
  controller.abort();

  await assert.rejects(readPromise, { name: "AbortError" });
  assert.equal(calls.at(-1).method, "request.cancel");
  assert.match(calls.at(-1).params.requestId, /^tcp-read:/);

  delete globalThis.__SKYLANE_RUNTIME__;
});
