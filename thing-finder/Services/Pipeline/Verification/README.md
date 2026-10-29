# Verification Pipeline

> Updated 2026-10-27 for the `gpt-6-luna` migration (version 1.2.2). See [Status](#10-status).

The verification subsystem decides whether a tracked vehicle candidate is the rider's car (or, in paratransit mode, the target bus). It crops each candidate from the camera frame, sends it to a remote verifier, and writes the result (`full`, `partial`, `unknown`, `rejected`) to `CandidateStore`. Navigation announces only verified candidates.

It chooses between three verifiers:

- **TrafficEyeVerifier**: TrafficEye MMR API (make/model/color/view/plate) followed by an OpenAI text comparison against the user's description.
- **TwoStepVerifier**: pure LLM. One vision call extracts vehicle attributes, a second text call compares them to the description.
- **AdvancedLLMVerifier**: one vision call that returns a match/unclear/reject verdict. Used for buses and paratransit (route numbers, logos).

`VerifierSelector` picks one per call, based on `VerificationConfig.strategy` and the candidate's attempt counters.

---

## 1  Architecture

```
FramePipelineCoordinator
          |  tick(pixelBuffer, ..., store)   every frame
          v
+------------------+
|  VerifierService |  filtering, throttling, offline pause, cropping, store updates, OCR
+---------+--------+
          |  verify(image, candidate, store)
          v
+------------------+
| VerifierSelector |  strategy -> verifier, counter reset, 10 s timeout, error -> outcome,
+---------+--------+  APIHealthMonitor reporting
          |
          v
+--------------------+-----------------+---------------------+
| TrafficEyeVerifier | TwoStepVerifier | AdvancedLLMVerifier |
+--------------------+-----------------+---------------------+
```

There is no separate `VerificationPolicy` type; that logic was merged into `VerifierSelector`.

### Components

| File | Responsibility |
|------|----------------|
| `VerifierService.swift` | Frame-driven orchestrator (`tick`). Filters `.unknown` candidates, applies the batch throttle, bbox filters and per-candidate throttle, pauses while offline, crops, calls the selector, increments attempt counters, maps outcomes to `MatchStatus`. |
| `VerifierService+OCR.swift` | `enqueueOCR`: on-device license-plate OCR and Levenshtein matching for `.partial` candidates. |
| `VerifierSelector.swift` | Instantiates only the verifiers the strategy needs, selects one per call, resets the opposite counter, applies the per-call timeout, converts thrown errors into retryable outcomes, reports to `APIHealthMonitor`. Defines `VerificationError.timeout`. |
| `VerificationConfig.swift` | `VerifierStrategy` enum and `VerificationConfig` (expected plate, OCR settings, per-candidate interval, strategy). |
| `ImageVerifier.swift` | `ImageVerifier` protocol and the shared `VerificationOutcome` struct. |
| `TrafficEyeVerifier.swift` | Blur gate, TrafficEye recognition call, early plate check, info-quality gate, OpenAI comparison. Accepts an injected `URLSessionProtocol` and API keys (used by tests). |
| `TwoStepVerifier.swift` | LLM extract (vision) then LLM compare (text). Defines `TwoStepError`. |
| `AdvancedLLMVerifier.swift` | Single vision call with a 3-field verdict tool, prompted for transit vehicles. |
| `NetworkErrorClassifier.swift` | Classifies errors as connectivity-related (`URLError` offline/timeout/DNS codes, `VerificationError.timeout`, `TwoStepError.networkError`). |
| `OCREngine.swift` | `OCREngine` protocol and `OCRResult`, so OCR can be mocked. |
| `VisionOCREngine.swift` | Production OCR with `VNRecognizeTextRequest` (en-US, no language correction, `minimumTextHeight` 0.1). Output is uppercased with non-alphanumerics stripped. |

Related code outside this folder: `Models/OpenAIModel.swift` (request/response types, shared model name), `Core/Candidate.swift` (`RejectReason`, `VerificationTracker`, `VehicleView`), `Utilities/String+Levenshtein.swift`, `Utilities/Networking/APIHealthMonitor.swift`.

### Wiring

`AppContainer.makePipeline` builds one `VerifierService` per search:

- `strategy` is `.paratransit` when `isParatransitMode` is true, otherwise `.hybrid`. `.llmOnly` and `.trafficEyeOnly` are not used by the app today; they exist for tests and experiments.
- `DescriptionParser.extractPlate(from:)` pulls a plate out of the description. `shouldRunOCR` is true only when the target classes include car, truck, bus or van **and** a plate was found. The plate becomes `expectedPlate`.
- All other `VerificationConfig` values use their defaults.

---

## 2  Strategies

| Strategy | Used when | Verifiers instantiated | Selection |
|----------|-----------|------------------------|-----------|
| `.hybrid` (default) | Standard car search | TrafficEye, TwoStep | TrafficEye first, escalate to TwoStep (see section 3) |
| `.paratransit` | `isParatransitMode` | TrafficEye, AdvancedLLM | **Always AdvancedLLM.** TrafficEye is instantiated but never selected. |
| `.llmOnly` | Not wired in app | AdvancedLLM | Always AdvancedLLM, no counter resets |
| `.trafficEyeOnly` | Not wired in app | TrafficEye | Always TrafficEye, no counter resets |

The doc comments in `VerificationConfig.swift` and the header of `VerifierSelector.swift` still describe `.paratransit` as a TrafficEye/AdvancedLLM escalation loop. The code in `selectVerifier` returns `.llm` unconditionally; `maxTrafficEyeRetriesParatransit` (1) and `maxLLMRetriesParatransit` (3) are unused. Restoring the loop means reusing the hybrid logic with those constants.

Verifier names returned with each outcome: `"TrafficEye"`, `"LLM"` (TwoStep in hybrid), `"AdvancedLLM"`. `VerifierService` uses `name.contains("TrafficEye")` to decide which counter to bump and whether to stamp `lastMMRTime`.

---

## 3  Hybrid escalation

Constants in `VerifierSelector.swift`: `maxTrafficEyeRetries = 1`, `maxLLMRetries = 3`.

```
selectVerifier(candidate):
  if llmAttempts     >= 3 -> TrafficEye
  if trafficAttempts >= 1 -> TwoStep
  else                    -> TrafficEye

on select TrafficEye: llmAttempts     = 0
on select TwoStep:    trafficAttempts = 0
on any non-match:     VerifierService increments the counter of the verifier that ran
```

- **TrafficEye first.** After **one** failure (any non-match, including a TrafficEye mismatch, which is not a hard reject in hybrid mode), escalate to TwoStepVerifier. Only TwoStep's mismatch hard-rejects. TrafficEye reads with infoQ < 0.85 skip the LLM and retry.
- **Failures include local rejects.** Blurry crops, network errors and timeouts all count as non-matches and increment `trafficAttempts`.
- **Exception:** a high-confidence plate mismatch from TrafficEye (`licensePlateMismatch`) is still a hard reject in hybrid mode.
- **Effective cycle is strict alternation.** Because selecting one engine zeroes the other counter, the sequence for a candidate that keeps failing retryably is TrafficEye, TwoStep, TrafficEye, TwoStep, ... `llmAttempts` never exceeds 1 in practice, so `maxLLMRetries = 3` only matters for hand-built counter states (as in `VerifierSelectorTests`).
- Rationale (from the code comment): a confident TrafficEye misread cannot be told apart from a correct read by score, so every non-match gets a TwoStep second opinion. In the real-image eval this raised rider's-car match from 75% to 90%, with strict false match going from 0.3% to 1.0%.

---

## 4  Per-frame flow (`VerifierService.tick`)

1. Snapshot the store and take candidates with `matchStatus == .unknown`.
2. If the target description is empty, promote all of them to `.full` (no verification).
3. Return early if there is nothing to verify and no `.partial` candidates.
4. **OCR pass** (only if `shouldRunOCR`): for each `.partial` candidate with `ocrAttempts < maxOCRRetries`, call `enqueueOCR`. This runs on every tick, before the batch throttle.
5. **Batch throttle**: skip if less than `minVerifyInterval` (1 s) since the last batch.
6. **Offline pause**: skip if `NetworkMonitor.isConnected` is false. `lastVerifyBatch` is not updated, so verification resumes on the next tick after reconnecting.
7. Set `lastVerifyBatch = now`. For each candidate:
   1. Skip if bbox area < 1% of the frame (the inline comment says 15%; the code uses 0.01).
   2. Skip if bbox height/width > 3.
   3. Skip if less than `perCandidateMMRInterval` (0.8 s) since `lastMMRTime`.
   4. Crop from the full frame. Set status `.unknown` -> `.waiting`.
   5. `selector.verify(...)`. On result:
      - Update `view`/`viewScore` if provided; stamp `lastMMRTime` if TrafficEye ran.
      - Non-match: increment `trafficAttempts` or `llmAttempts`.
      - Match, and (`!shouldRunOCR` or `isPlateMatch`): `.full`.
      - Match with OCR required: `.partial`, then `enqueueOCR`.
      - Non-match with retryable reason, or hybrid TrafficEye `wrongModelOrColor`: `.unknown` (retry).
      - Non-match with any other reason: `.rejected`.
      - `rejectReason` and `detectedDescription` are stored on the candidate.

The `.failure` branch of the sink in `VerifierService` is effectively unreachable because the selector's `.catch` converts every error into an outcome.

---

## 5  VerificationOutcome and reject reasons

`VerificationOutcome` (`ImageVerifier.swift`):

| Field | Meaning |
|-------|---------|
| `isMatch` | Verifier accepted the candidate. |
| `description` | Detected description (for example "GRAY Toyota Camry"), plate text, or a short failure tag ("blurry", "encode_failed"). |
| `rejectReason` | `RejectReason?`; `.success` on match. |
| `isPlateMatch` | TrafficEye's plate exactly matched `expectedPlate`; skips OCR. |
| `vehicleView`, `viewScore` | Observed angle and its score (TwoStep uses `visible_fraction` as the score). |
| `didCompleteNetworkRequest` | False for local rejects (blur, encode failure) and thrown errors. Only outcomes with `true` can call `APIHealthMonitor.recordSuccess()`. |

`RejectReason` (`Core/Candidate.swift`):

| Retryable (-> `.unknown`) | Hard reject (-> `.rejected`) |
|---------------------------|------------------------------|
| `unclearImage`, `lowConfidence`, `insufficientInfo`, `apiError`, `ambiguous`, `licensePlateNotVisible`, `networkError` | `wrongModelOrColor` (except from TrafficEye in hybrid), `licensePlateMismatch`, `wrongObjectClass` |

### Per-verifier decision rules

**TrafficEyeVerifier**

| Condition | Outcome |
|-----------|---------|
| `blurScore` nil or >= 0.1 | `unclearImage`, no network call |
| JPEG encode fails | `apiError`, no network call |
| Transport error from TrafficEye | `networkError` if connectivity-related, else `apiError` (not counted as completed request) |
| `expectedPlate` set and detected plate equals it (spaces removed, uppercased) | match, `isPlateMatch = true`, no LLM call |
| Detected plate score >= 0.9, same length, different text | `licensePlateMismatch` (hard reject) |
| No MMR in response | `apiError` ("No vehicle detected") |
| `infoQ = 0.5*make + 0.3*model + 0.2*color` < 0.85 (`minInfoQuality`) | `insufficientInfo`, no LLM call |
| LLM `semantic_reason` = match / maybe / mismatch | match / `lowConfidence` / `wrongModelOrColor` |

Errors from the OpenAI comparison call (transport, decode, missing tool call) are thrown and mapped by the selector. `confidenceThresholdMatch` (0.80) and `confidenceThresholdAmbiguous` (0.60) are declared but unused.

**TwoStepVerifier**

| Condition | Outcome |
|-----------|---------|
| Extract step has no tool call | throws `TwoStepError.noToolResponse` -> `apiError` |
| `visible_fraction` < 0.5 | throws `.occluded` -> `unclearImage` |
| Extract `confidence` < 0.9 | throws `.lowConfidence` -> `lowConfidence` |
| Compare step: quality (`0.5*make + 0.3*model + 0.2*color` scores) >= 0.85 | match / maybe -> `lowConfidence` / mismatch -> `wrongModelOrColor` (hard reject) |
| Compare step: quality < 0.85 | match, else `insufficientInfo` |

`confidenceThreshold` (0.90) and `matchToolSchema` are declared but unused.

**AdvancedLLMVerifier**

| Verdict | Outcome |
|---------|---------|
| `match` with confidence >= 0.80 | match (description = target text) |
| `match` with confidence < 0.80 | `lowConfidence` |
| `reject` | `wrongModelOrColor` (hard reject) |
| `unclear` or anything else | `ambiguous` |

### Error mapping in `VerifierSelector`

| Thrown error | Reason |
|--------------|--------|
| `VerificationError.timeout` (10 s) | `networkError` |
| `TwoStepError` | `noToolResponse` -> `apiError`, `networkError` -> `networkError`, `occluded` -> `unclearImage`, `lowConfidence` -> `lowConfidence` |
| Other | `networkError` if `NetworkErrorClassifier` says connectivity, else `apiError` |

All mapped outcomes have `didCompleteNetworkRequest = false`.

---

## 6  License-plate OCR

Runs only when `shouldRunOCR` is true (a plate was parsed from the description). Two plate paths exist:

1. **TrafficEye plate** (inside `TrafficEyeVerifier`, also runs whenever `expectedPlate` is set): exact match gives `.full` immediately; high-confidence same-length mismatch hard-rejects.
2. **On-device OCR** (`VerifierService+OCR.swift`): for candidates promoted to `.partial` by a make/model/color match.

On-device OCR, on a `.userInitiated` global queue:

1. Crop the candidate's current bbox from the full frame.
2. `ocrEngine.recognize(crop:)`.
3. If confidence >= `ocrConfidenceMin` (0.2) and text matches `regex` (`^[A-Z0-9]{5,8}$`, case-insensitive), compute Levenshtein distance to `expectedPlate`:
   - <= `maxEditsForMatch` (1): `.full`
   - <= `maxEditsForContinue` (2): stays `.partial`
   - otherwise: `.rejected`
4. If confidence or regex fails, stays `.partial`.
5. Always increments `ocrAttempts` and stores `ocrText`.

`maxOCRRetries` (30) only limits which partials `tick` re-enqueues; a candidate that never gets a usable read stays `.partial` indefinitely. The config comment notes 30 is a legacy value that could be reduced now that edit-distance matching exists.

---

## 7  Models, endpoints, request parameters

| Verifier | Endpoint | Model | Calls per verify | Input |
|----------|----------|-------|------------------|-------|
| TrafficEye | `POST https://trafficeye.ai/recognition` (multipart: `request` JSON with `saveImage: false`, `tasks: ["DETECTION","OCR","MMR"]`; `file` JPEG q=1.0). Header `apiKey`. | n/a | 1 | Crop |
| TrafficEye (compare) | `POST https://api.openai.com/v1/chat/completions` | `ChatCompletionRequest.verifierModel` | 1 (skipped if plate decides or infoQ < 0.85) | MMR JSON + description (text only) |
| TwoStep | same OpenAI endpoint | `verifierModel` | 2 (extract: vision; compare: text) | Crop as JPEG q=1.0, sent with a `data:image/png` URL prefix |
| AdvancedLLM | same OpenAI endpoint | `verifierModel` | 1 (vision) | Description + crop as JPEG q=0.7 |

Shared request shape (`Models/OpenAIModel.swift`, `ChatCompletionRequest`):

| Param | Value |
|-------|-------|
| `model` | `verifierModel` = `"gpt-6-luna"` |
| `tool_choice` | `"required"` |
| `tools` | one function per call, `strict: true`, `additionalProperties: false` |
| `max_completion_tokens` | 300 for every call |
| `reasoning_effort` | `"none"` |

Tool functions: `submit_match_decision` (`probability_match`, `semantic_reason` in match/maybe/mismatch) for both compare steps; `extract_vehicle_info` (make, model, color, view, per-attribute scores, confidence, visible_fraction) for TwoStep step 1; `verify_match` (verdict, confidence, reason) for AdvancedLLM. `probability_match` is logged but not used in decisions.

API caveats that constrain these params (see [`evals/realworld/README.md`](../../../../evals/realworld/README.md#api-notes-that-affect-the-swift-code)):

- `gpt-6-luna` supports function calling on Chat Completions only with `reasoning_effort: "none"`.
- Reasoning models take `max_completion_tokens`, not `max_tokens`, and the budget includes reasoning tokens.

All calls go through the CurbToCar Cloudflare Worker (`proxy/`), which holds the OpenAI and TrafficEye keys; the app never ships them. The proxy exposes the same paths (`/v1/chat/completions`, `/recognition`), so the endpoints in the table above are what the Worker forwards to. `APIProxy` (`Utilities/Networking/APIProxy.swift`) reads `PROXY_BASE_URL` and `PROXY_APP_TOKEN` from `Info.plist` and adds `X-App-Token` and a per-install `X-Device-Id` header. A missing URL falls back to an unreachable host, so requests fail at the network rather than at startup. TwoStep and AdvancedLLM use `APIProxy.shared` and `URLSession.shared` directly; only TrafficEye accepts an injected proxy and session (tests use `APIProxy.test`, host `proxy.test`).

Latency (historical, measured with `gpt-4.1-mini`): TrafficEye path about 1.9 s, TwoStep and AdvancedLLM 4-5 s. The eval reports the `gpt-6-luna` comparison call as about 0.5 s slower at p50 and 1 s slower at p95 than `gpt-4.1-mini`.

---

## 8  Concurrency, throttling, health

| Mechanism | Value | Where |
|-----------|-------|-------|
| Batch throttle | `minVerifyInterval` = 1 s between batches | `VerifierService` |
| Per-candidate throttle | `perCandidateMMRInterval` = 0.8 s since `lastMMRTime` (stamped only when TrafficEye ran) | `VerificationConfig` |
| One request in flight per candidate | Candidate moves to `.waiting`, and only `.unknown` candidates are picked up | `VerifierService` |
| Per-call timeout | 10 s, scheduled on `DispatchQueue.main` | `VerifierSelector` |
| Offline pause | Batches skipped while `NetworkMonitor.isConnected` is false; OCR continues | `VerifierService` |
| API health | `.networkError` outcomes -> `recordFailure(isConnectivityRelated: true)`; outcomes with `didCompleteNetworkRequest` -> `recordSuccess()`. `APIHealthMonitor` flags degradation after 3 consecutive connectivity failures (default). | `VerifierSelector` |

There is no global cap on concurrent requests: every eligible candidate in a batch is sent at once. There are no automatic HTTP retries; retry happens by leaving the candidate `.unknown` for a later tick.

---

## 9  Testing

Unit tests live in `thing-finderTests/Verification/`. Network responses are canned in `thing-finderTests/Fixtures/TestAPIResponses.swift` (TrafficEye success, medium/low confidence, `trafficEyeBelowInfoGate` with infoQ 0.72, no vehicle, plate only, rear view; OpenAI match/mismatch/maybe/no tool call/malformed; TwoStep extraction/occluded).

| Test class | Covers |
|------------|--------|
| `VerifierSelectorTests` | Selection per strategy, hybrid escalation thresholds (uses `VerifierSelector.maxTrafficEyeRetries`), counter resets, paratransit always AdvancedLLM, error -> retryable outcome, APIHealthMonitor reporting |
| `VerifierServiceTests` | bbox size/aspect filters, auto-promote without description, batch and per-candidate throttles, `.waiting` status, offline pause and resume |
| `TrafficEyeVerifierTests` | Blur gate, no vehicle, network vs malformed responses, low-confidence and below-gate (0.85) MMR, URL session injection |
| `TwoStepVerifierTests` | Init and `TwoStepError` cases only (no network mocking; the verifier uses `URLSession.shared`) |
| `OCREngineTests` | `OCRResult`, Levenshtein distance, plate matching tolerance |
| `NetworkErrorClassifierTests` | Connectivity classification |

Gaps: no test covers the hybrid rule that a TrafficEye `wrongModelOrColor` leaves the candidate `.unknown`, the plate early-match/mismatch path, `AdvancedLLMVerifier` decisions, or `enqueueOCR` status transitions.

Build and test commands (simulator selection, `-only-testing:thing-finderTests/VerifierSelectorTests`, etc.) are in [`.agents/skills/ios-build-test/SKILL.md`](../../../../.agents/skills/ios-build-test/SKILL.md).

---

## 10  Status

Version 1.2.2 changed this folder, `Models/OpenAIModel.swift` and the verification tests to migrate off `gpt-4.1-mini`, which OpenAI removes on 2027-01-14, and to apply findings from the real-image eval:

| Change | Before | After |
|--------|--------|-------|
| Model for all verifiers | `gpt-4.1-mini` hard-coded in each verifier | `ChatCompletionRequest.verifierModel = "gpt-6-luna"` |
| Token param | `max_tokens` 50 (compare) / 100 (extract, AdvancedLLM) | `max_completion_tokens` 300 everywhere, `reasoning_effort: "none"` |
| TrafficEye info-quality gate | infoQ < 0.4 skipped; 0.4-0.85 reached the LLM with a weaker decision table | infoQ < 0.85 skipped (`minInfoQuality`); only high-quality reads reach the LLM |
| Hybrid escalation | `maxTrafficEyeRetries = 3` | `1` |
| TrafficEye mismatch in hybrid | Hard reject | Retry via TwoStep; only TwoStep's mismatch hard-rejects |

Not yet done or still inconsistent:

- `.paratransit` docs (in `VerificationConfig.swift` and `VerifierSelector.swift`) describe an escalation loop that the code does not implement.
- TwoStep keeps its own 0.85/0.4 quality table; only TrafficEye was simplified.
- `.agents/skills/verifier-evals/SKILL.md` still says `gpt-4.1-mini` is used in all three Swift verifiers.

---

## 11  Evals

- Real-image eval (model and prompt choice, TrafficEye bottleneck analysis, hybrid replay): [`evals/realworld/README.md`](../../../../evals/realworld/README.md). Full report: `evals/results/realworld/full1_analysis.md`.
- Older synthetic harness: [`evals/README.md`](../../../../evals/README.md).
- Agent workflow and cost gate for eval runs: `.agents/skills/verifier-evals/SKILL.md`.

---

## 12  Future work

- Multi-frame voting (require N agreeing positives within T seconds).
- Adaptive timing based on real-world cost data.
- Smarter side-view heuristics using `VehicleView`. The eval shows TwoStep is weak on side views (52-58% true match vs about 70% for TrafficEye).
- Decide whether `.paratransit` should restore the TrafficEye/AdvancedLLM loop or drop TrafficEye instantiation.
- Remove unused thresholds and schemas listed in section 5.
