// CurbToCar API proxy. Holds the OpenAI and TrafficEye keys so the iOS app never ships them.
// Only the two endpoints the app uses are forwarded, with model/token/size limits and per-device rate limits.

const OPENAI_URL = "https://api.openai.com/v1/chat/completions";
const TRAFFICEYE_URL = "https://trafficeye.ai/recognition";

const DEFAULT_ALLOWED_MODELS = "gpt-6-luna";
const DEFAULT_MAX_COMPLETION_TOKENS = 300;
// The app sends uncompressed-quality JPEG crops (base64 in chat bodies). A full 4032x3024 frame
// can reach ~10 MB, ~13 MB as base64; 16 MB covers it while staying well under Worker memory.
const MAX_CHAT_BODY_BYTES = 16 * 1024 * 1024;
const MAX_RECOGNITION_BODY_BYTES = 16 * 1024 * 1024;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return json(200, { ok: true });
    }

    const route = ROUTES[url.pathname];
    if (!route) return json(404, { error: "not_found" });
    if (request.method !== "POST") return json(405, { error: "method_not_allowed" });

    if (!env.APP_TOKEN || !timingSafeEqual(request.headers.get("X-App-Token") ?? "", env.APP_TOKEN)) {
      return json(401, { error: "unauthorized" });
    }

    const deviceId = request.headers.get("X-Device-Id") ?? "";
    if (!/^[A-Za-z0-9-]{8,64}$/.test(deviceId)) {
      return json(400, { error: "missing_device_id" });
    }

    const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
    if (!(await allowed(env.DEVICE_LIMITER, `device:${deviceId}`)) || !(await allowed(env.IP_LIMITER, `ip:${ip}`))) {
      return json(429, { error: "rate_limited" });
    }

    return route(request, env);
  },
};

const ROUTES = {
  "/v1/chat/completions": handleChat,
  "/recognition": handleRecognition,
};

async function handleChat(request, env) {
  if (!(request.headers.get("Content-Type") ?? "").startsWith("application/json")) {
    return json(415, { error: "unsupported_media_type" });
  }

  const raw = await readLimited(request, MAX_CHAT_BODY_BYTES);
  if (raw === null) return json(413, { error: "payload_too_large" });

  let body;
  try {
    body = JSON.parse(new TextDecoder().decode(raw));
  } catch {
    return json(400, { error: "invalid_json" });
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return json(400, { error: "invalid_json" });
  }

  const allowedModels = (env.ALLOWED_MODELS ?? DEFAULT_ALLOWED_MODELS).split(",").map((m) => m.trim());
  if (!allowedModels.includes(body.model)) {
    return json(400, { error: "model_not_allowed" });
  }

  const maxTokens = Number(env.MAX_COMPLETION_TOKENS ?? DEFAULT_MAX_COMPLETION_TOKENS);
  const requested = Number.isFinite(body.max_completion_tokens) ? body.max_completion_tokens : maxTokens;
  body.max_completion_tokens = Math.min(requested, maxTokens);
  delete body.max_tokens;
  delete body.n;
  delete body.stream;

  const upstream = await fetch(OPENAI_URL, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.OPENAI_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  return passThrough(upstream);
}

async function handleRecognition(request, env) {
  const contentType = request.headers.get("Content-Type") ?? "";
  if (!contentType.startsWith("multipart/form-data")) {
    return json(415, { error: "unsupported_media_type" });
  }

  const raw = await readLimited(request, MAX_RECOGNITION_BODY_BYTES);
  if (raw === null) return json(413, { error: "payload_too_large" });

  const upstream = await fetch(TRAFFICEYE_URL, {
    method: "POST",
    headers: {
      apiKey: env.TRAFFICEYE_KEY,
      "Content-Type": contentType,
    },
    body: raw,
  });
  return passThrough(upstream);
}

// Returns the body bytes, or null if it exceeds maxBytes.
async function readLimited(request, maxBytes) {
  const declared = Number(request.headers.get("Content-Length"));
  if (Number.isFinite(declared) && declared > maxBytes) return null;
  const buffer = await request.arrayBuffer();
  return buffer.byteLength > maxBytes ? null : buffer;
}

async function allowed(limiter, key) {
  if (!limiter) return true;
  const { success } = await limiter.limit({ key });
  return success;
}

function passThrough(upstream) {
  return new Response(upstream.body, {
    status: upstream.status,
    headers: { "Content-Type": upstream.headers.get("Content-Type") ?? "application/json" },
  });
}

function json(status, payload) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function timingSafeEqual(a, b) {
  const encoder = new TextEncoder();
  const left = encoder.encode(a);
  const right = encoder.encode(b);
  let diff = left.length ^ right.length;
  for (let i = 0; i < Math.max(left.length, right.length); i++) {
    diff |= (left[i] ?? 0) ^ (right[i] ?? 0);
  }
  return diff === 0;
}
