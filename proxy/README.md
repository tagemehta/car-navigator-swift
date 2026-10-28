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
Requests are rate-limited per device (150 per 10 s) and per IP (600 per 10 s), about 2× the app's worst case. See `DesignDecisions.md` → API Key Security for the derivation. Anything else is a 404.

## Secrets

Set with `wrangler secret put <NAME>`, never committed: `OPENAI_KEY`, `TRAFFICEYE_KEY`, `APP_TOKEN`.
The app's `PROXY_APP_TOKEN` in `thing-finder/Secrets.xcconfig` must equal `APP_TOKEN`.
Rotating a secret takes effect immediately with no redeploy.

## Rollout

The reasoning behind this design is in `thing-finder/Docs/DesignDecisions.md` → API Key Security.

1. **Merge and release the proxy build.** Merge PR #40, then test a TestFlight build on a real iPhone. In the Worker logs (`wrangler tail`), confirm that both verifiers' requests arrive and return 200. Then submit to the App Store.
2. **Limit the old key right away.** Builds released before the proxy call OpenAI directly with the old key, and that key is being scraped. Set a low monthly budget on its OpenAI project now so a drain is capped while users update.
3. **Revoke the old key about two weeks after release,** or sooner if the budget is being hit. With a few thousand users, most update within 1–2 weeks. Revoke the old TrafficEye key at the same time if it was rotated.

   What older builds do after revocation: OpenAI returns an error the app can't decode. `VerifierSelector.outcomeForError` turns that into `isMatch: false` with reason `.apiError`, which is retryable (`Candidate.swift:170`). The app never announces a false match. The car just never gets confirmed. Because it isn't classified as a connectivity failure, those users hear no "connection" warning either. If that's not acceptable, keep the old key alive longer, under its budget cap.
4. **Monitor.** `scripts/api_health_check.py` runs from cron every 12 hours, checks both APIs through the proxy, and posts the result to Slack each run. Request volume is in the Cloudflare dashboard (Workers → `curbtocar-proxy` → Metrics). Rate-limited (429) and unauthorized (401) responses show up in `wrangler tail`.
5. **App Attest only if needed.** Move to App Attest (soft mode first) if traffic stops looking like real users. The triggers and plan are in `DesignDecisions.md` → App Attest.

### Rotating secrets

| Secret | How | App release needed? |
|---|---|---|
| `OPENAI_KEY`, `TRAFFICEYE_KEY` | Create the new key, run `wrangler secret put <NAME>`, then revoke the old key | No; takes effect immediately |
| `APP_TOKEN` | Run `wrangler secret put APP_TOKEN` and set the same value as `PROXY_APP_TOKEN` in `Secrets.xcconfig` | **Yes.** Builds with the old token get 401 until users update, so only rotate it if it's being abused |

## Commands

```bash
npm test          # node:test, no dependencies
wrangler deploy   # or: wrangler deploy --dry-run
wrangler tail     # live request logs
```

The app token can still be extracted from a shipped build. The per-device limits, model and token caps, and the OpenAI project budget limit what that can cost. App Attest is deferred; see Rollout step 5.
