# curbtocar-proxy

Cloudflare Worker that holds the OpenAI and TrafficEye keys so the iOS app never ships them.
Deployed at `https://curbtocar-proxy.curbtocar.workers.dev`.

## Routes

| Route | Forwards to | Limits |
|---|---|---|
| `GET /health` | nothing (no auth) | |
| `POST /v1/chat/completions` | `api.openai.com/v1/chat/completions` | model must be in `ALLOWED_MODELS`; `max_completion_tokens` capped at `MAX_COMPLETION_TOKENS`; `n`, `stream`, `max_tokens` stripped; body ≤ 4 MB |
| `POST /recognition` | `trafficeye.ai/recognition` | multipart only; body ≤ 5 MB |

Every route except `/health` needs `X-App-Token` (matches the `APP_TOKEN` secret) and `X-Device-Id`.
Requests are rate-limited per device (60/min) and per IP (120/min). Anything else is a 404.

## Secrets

Set with `wrangler secret put <NAME>`, never committed: `OPENAI_KEY`, `TRAFFICEYE_KEY`, `APP_TOKEN`.
The app's `PROXY_APP_TOKEN` in `thing-finder/Secrets.xcconfig` must equal `APP_TOKEN`.
Rotating a secret takes effect immediately with no redeploy.

## Commands

```bash
npm test          # node:test, no dependencies
wrangler deploy   # or: wrangler deploy --dry-run
wrangler tail     # live request logs
```

The app token is still extractable from a shipped build; the per-device limits and model/token caps bound what it can cost. App Attest is the planned fix.
