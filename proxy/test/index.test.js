import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";

const BASE = "https://proxy.test";
const DEVICE = "0F8FAD5B-D9CB-469F-A165-70867728950E";

let upstreamCalls;
let realFetch;

beforeEach(() => {
  upstreamCalls = [];
  realFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    upstreamCalls.push({ url, init });
    return new Response(JSON.stringify({ upstream: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  };
});

afterEach(() => {
  globalThis.fetch = realFetch;
});

function env(overrides = {}) {
  return {
    APP_TOKEN: "app-token",
    OPENAI_KEY: "openai-secret",
    TRAFFICEYE_KEY: "trafficeye-secret",
    ...overrides,
  };
}

function chat(body, headers = {}) {
  return new Request(`${BASE}/v1/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-App-Token": "app-token",
      "X-Device-Id": DEVICE,
      ...headers,
    },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

const validChat = { model: "gpt-6-luna", messages: [], max_completion_tokens: 300 };

test("health needs no token", async () => {
  const res = await worker.fetch(new Request(`${BASE}/health`), env());
  assert.equal(res.status, 200);
});

test("unknown path is 404 and never reaches upstream", async () => {
  const res = await worker.fetch(new Request(`${BASE}/v1/models`, { method: "POST" }), env());
  assert.equal(res.status, 404);
  assert.equal(upstreamCalls.length, 0);
});

test("GET on a route is 405", async () => {
  const res = await worker.fetch(new Request(`${BASE}/v1/chat/completions`), env());
  assert.equal(res.status, 405);
});

test("wrong or missing app token is 401", async () => {
  for (const token of ["nope", ""]) {
    const res = await worker.fetch(chat(validChat, { "X-App-Token": token }), env());
    assert.equal(res.status, 401);
  }
  assert.equal(upstreamCalls.length, 0);
});

test("unset APP_TOKEN rejects everything", async () => {
  const res = await worker.fetch(chat(validChat, { "X-App-Token": "" }), env({ APP_TOKEN: "" }));
  assert.equal(res.status, 401);
});

test("missing device id is 400", async () => {
  const res = await worker.fetch(chat(validChat, { "X-Device-Id": "" }), env());
  assert.equal(res.status, 400);
});

test("rate limited device is 429", async () => {
  const limiter = { limit: async () => ({ success: false }) };
  const res = await worker.fetch(chat(validChat), env({ DEVICE_LIMITER: limiter }));
  assert.equal(res.status, 429);
  assert.equal(upstreamCalls.length, 0);
});

test("chat is forwarded with the server key and sanitized body", async () => {
  const res = await worker.fetch(
    chat({ ...validChat, max_completion_tokens: 5000, n: 4, stream: true, max_tokens: 9000 }),
    env(),
  );
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { upstream: true });

  const [call] = upstreamCalls;
  assert.equal(call.url, "https://api.openai.com/v1/chat/completions");
  assert.equal(call.init.headers.Authorization, "Bearer openai-secret");
  const sent = JSON.parse(call.init.body);
  assert.equal(sent.max_completion_tokens, 300);
  assert.equal(sent.n, undefined);
  assert.equal(sent.stream, undefined);
  assert.equal(sent.max_tokens, undefined);
});

test("disallowed model is 400", async () => {
  const res = await worker.fetch(chat({ ...validChat, model: "gpt-6" }), env());
  assert.equal(res.status, 400);
  assert.equal(upstreamCalls.length, 0);
});

test("invalid JSON is 400", async () => {
  const res = await worker.fetch(chat("{not json"), env());
  assert.equal(res.status, 400);
});

test("oversized chat body is 413", async () => {
  const big = { ...validChat, pad: "x".repeat(4 * 1024 * 1024 + 1) };
  const res = await worker.fetch(chat(big), env());
  assert.equal(res.status, 413);
});

test("upstream error status is passed through", async () => {
  globalThis.fetch = async () =>
    new Response(JSON.stringify({ error: "quota" }), { status: 429, headers: { "Content-Type": "application/json" } });
  const res = await worker.fetch(chat(validChat), env());
  assert.equal(res.status, 429);
});

test("recognition forwards multipart with the TrafficEye key", async () => {
  const req = new Request(`${BASE}/recognition`, {
    method: "POST",
    headers: {
      "Content-Type": "multipart/form-data; boundary=Boundary-1",
      "X-App-Token": "app-token",
      "X-Device-Id": DEVICE,
    },
    body: "--Boundary-1\r\n\r\nimage\r\n--Boundary-1--\r\n",
  });
  const res = await worker.fetch(req, env());
  assert.equal(res.status, 200);

  const [call] = upstreamCalls;
  assert.equal(call.url, "https://trafficeye.ai/recognition");
  assert.equal(call.init.headers.apiKey, "trafficeye-secret");
  assert.equal(call.init.headers["Content-Type"], "multipart/form-data; boundary=Boundary-1");
});

test("recognition rejects non-multipart", async () => {
  const req = new Request(`${BASE}/recognition`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-App-Token": "app-token", "X-Device-Id": DEVICE },
    body: "{}",
  });
  const res = await worker.fetch(req, env());
  assert.equal(res.status, 415);
});
