# Design Decisions & Tuning Rationale

Explains why key thresholds and architectural choices in Thing Finder are what they are. Superseded decisions are kept, marked, and point to what replaced them.
Last verified against code: 2026-10-27

Status legend: **Current** = matches code. **Superseded** = replaced; historical. **Legacy** = still in code but no longer pulling its weight.

---

## Quick Reference

| Value | Current | File |
| ----- | ------- | ---- |
| Drift repair stride | 15 frames | `Services/Pipeline/DriftRepairService.swift` |
| Drift repair cosine similarity | > 0.90 | `DriftRepairService.swift` |
| Miss threshold (drop / mark lost) | 90 frames (~3 s at 30 fps) | `Services/Pipeline/CandidateLifecycleService.swift` |
| Detection overlap for "seen this frame" | IoU > 0.1 | `CandidateLifecycleService.swift` |
| Rejected candidate removal | 10 s after last update | `CandidateLifecycleService.swift` |
| Candidate cap | 10 non-lost candidates | `CandidateLifecycleService.swift` |
| Duplicate detection | IoU > 0.6 OR center distance < 0.15 | `Core/CandidateStore.swift` |
| Verifier escalation (hybrid) | TrafficEye 1 fail, then LLM; LLM 3 fails, then TrafficEye (was 3 / 3 in HEAD) | `Services/Pipeline/Verification/VerifierSelector.swift` |
| Per-call verification timeout | 10 s | `VerifierSelector.swift` |
| Verification batch interval | 1 s | `Services/Pipeline/Verification/VerifierService.swift` |
| Per-candidate re-verify interval | 0.8 s | `VerificationConfig.swift` |
| Min box area / max tallness to verify | 1% of image / h:w <= 3 | `VerifierService.swift` |
| OCR retries | 30 (legacy) | `VerificationConfig.swift` |
| Lost-target compass threshold | > 60°, rounded to 30° | `Utilities/MatchStatusSpeech.swift` |

---

## Pipeline Thresholds

### Drift Repair Stride (15 frames) — Current
**File:** `DriftRepairService.swift` (`repairStride: Int = 15`)

- Every 15 frames (~0.5 s at 30 fps) candidates are re-associated to fresh YOLO detections.
- Tradeoff: lower stride gives more accurate tracking but costs CPU/battery; higher stride accumulates Vision tracker drift. 15 was tuned empirically on device.

### Embedding Similarity Threshold (0.90) — Current
**File:** `DriftRepairService.swift` (`simThreshold: Float = 0.90`)

- Feature-print cosine similarity must exceed 0.90; best score wins, early exit at >= 0.99.
- Somewhat arbitrary: high enough to avoid false re-associations, low enough to tolerate small appearance changes.
- The center-distance penalty (max 0.40) is commented out because it added noise on semi-quick camera movement. The file header still mentions IoU/center thresholds; only similarity is used.

### Miss Threshold — Superseded (15 frames, replaced by 90 frames)
**File:** `CandidateLifecycleService.swift` (`missThreshold: Int = 90`)

- Original: 15 frames (~0.5 s). Changed to 90 frames (~3 s) in `fb54466` (2026-06-17) because brief occlusions and detection flicker dropped real candidates too often.
- A candidate's `missCount` resets when any detection overlaps it (IoU > 0.1). At the threshold: `.full` becomes `.lost`; `.lost` is kept; everything else is removed.
- The file header comment still says "default: 5 consecutive misses" (stale).

### Duplicate Detection (IoU > 0.6, center distance < 0.15) — Current
**File:** `CandidateStore.containsDuplicateOf`

- Either condition marks a new detection as a duplicate. `.lost` candidates are ignored, so a re-detected lost car can become a new candidate.
- Empirically tuned to avoid duplicate candidates for one car while keeping nearby distinct cars.

### Candidate Cap (10) — Current (added 2026-06-18, `aa02bb3`)
**File:** `CandidateLifecycleService.swift` (`candidateCap: Int = 10`)

- Limits Vision trackers and embeddings in dense scenes (parking lots); about 20 ms/frame of tracking on A15-class hardware.
- On ingest at the cap, the non-lost candidate with the highest `missCount` is evicted. `.partial`, `.full` and `.lost` are never evicted; if only those remain, the new detection is skipped.

### Ingest Gating — Current
- New detections are not ingested while a `.full` candidate exists (`CandidateStore.hasActiveMatch` checks `.full` only; `.partial` does not block ingest).

---

## Verification System

### Escalation Thresholds — Superseded (`VerificationPolicy.swift`, replaced by `VerifierSelector`)

Historical table (the file `VerificationPolicy.swift` no longer exists):

| Engine | Fail Threshold | Action |
|--------|----------------|--------|
| TrafficEye | 1 fail | Try side view |
| TrafficEye | 3 fails | Escalate to LLM |
| LLM | 2 fails | Back to TrafficEye |

Original rationale: TrafficEye is about 1.9 s per call (retry more), the LLM about 4–5 s (fewer retries).

### Verifier Escalation Policy — Current
**File:** `VerifierSelector.swift` (introduced in `4ae662f`, 2026-03-08, replacing Strategy → StrategyManager → Factory layering)

| Strategy | Used when | Selection |
| -------- | --------- | --------- |
| `.hybrid` | Default car search (`AppContainer`) | TrafficEye; after `maxTrafficEyeRetries = 1` failure, `TwoStepVerifier`; after `maxLLMRetries = 3` LLM failures, back to TrafficEye. Switching engines resets the other engine's counter. Loops until match or hard reject. |
| `.paratransit` | `isParatransitMode` | Always `AdvancedLLMVerifier`. The TrafficEye-first escalation constants exist but are not used (see comment in `selectVerifier`). |
| `.llmOnly` | Not wired in `AppContainer` | Always `AdvancedLLMVerifier` |
| `.trafficEyeOnly` | Not wired in `AppContainer` | Always TrafficEye |

- In hybrid mode a TrafficEye `.wrongModelOrColor` is not final: `VerifierService` treats it as retryable (candidate back to `.unknown`) so it escalates to TwoStep, and only TwoStep's mismatch hard-rejects.
- History: `maxTrafficEyeRetries` was 3 (committed HEAD as of 2026-10-27). The value 1 and the TrafficEye-mismatch escalation were uncommitted working-tree changes when this doc was verified; re-check after merge.
- Why 1 TrafficEye failure: a confident TrafficEye misread can't be distinguished from a correct read by score, so any non-match gets a TwoStep second opinion. Real-image eval: rider's car matched 75% to 90%; strict false match 0.3% to 1.0%.
- Every call has a 10 s timeout. Errors and timeouts become retryable rejections (`.networkError` / `.apiError` / `.unclearImage` / `.lowConfidence`), so the loop never dies on an exception.
- Outcomes feed `APIHealthMonitor`: network errors record a failure; only outcomes that actually completed a network request record success, so a thrown or unparseable request can't clear degradation (`a887eed`).

### Verification Rate Limits and Gates — Current
**File:** `VerifierService.swift`

- Batches at most every 1 s; each candidate at most every 0.8 s (`perCandidateMMRInterval`).
- Skips boxes under 1% of the image area or taller than 3:1 (people, poles).
- Skips network verification entirely while offline (`NetworkMonitor.isConnected == false`) without touching `lastVerifyBatch`, so verification resumes on the next tick after reconnecting. This is what makes "search paused" literal. On-device OCR is unaffected.

### OCR Retry Limit (30 attempts) — Legacy
**File:** `VerificationConfig.swift` (`maxOCRRetries = 30`)

- Originally high because OCR could be off by one character. Levenshtein matching now handles that (`maxEditsForMatch = 1`, `maxEditsForContinue = 2`), so this could be reduced.
- OCR only runs when the target classes include car/truck/bus/van and `DescriptionParser` found a plate in the description (`AppContainer`).

---

## Navigation Feedback

### Controller Split with Shared AnnouncementCache — Current (2026-06-09 onward)
**Files:** `Services/Pipeline/Navigation/*`

- `FrameNavigationManager` runs, in order: `NetworkFeedbackController`, `PreMatchFeedbackController`, `NavAnnouncer`, `DirectionSpeechController`, `DistanceMilestoneController`, `HapticBeepController`.
- Rationale: each controller owns one feedback concern and is unit-testable alone. A shared `AnnouncementCache` (`lastGlobal`, `lastByCandidate`, `priorityFrame`) lets controllers back off from each other. `Speaker.speak` interrupts the current utterance, so later controllers defer instead of cutting off connectivity warnings.
- See `NavigationBehavior.md` for exact phrases and timings.

### Change-Gated Direction Speech — Current; replaced repeating direction phrases
- Superseded: "{direction}, {distance} meters" on change and "Still {direction}…" every `speechRepeatInterval`.
- Current (`acaa0fd`, 2026-06-09): direction is spoken only on the first target frame and when the category changes, debounced by `speechChangeInterval` (4 s). Distance moved to `DistanceMilestoneController` (10 / 5 / 2 m, "almost there" at 1 m, 1.5 m hysteresis). Rationale: repeats were noisy; beeps carry continuous guidance.

### Silent Waiting, Rejection and Retry in MatchStatusSpeech — Current; replaced verbose status phrases
- Superseded: "Waiting for verification", "{desc} – {reason}" rejections, and retry phrases ("Picture too blurry, trying again", etc.) with 10 s / 8 s cooldowns.
- Current: `.waiting`, `.rejected`, `.unknown` return `nil`; `retryPhrase` always returns `nil`. Rejections are owned by `PreMatchFeedbackController` ("Not yours — {desc}", grouped to "Several cars nearby, still looking" when dense). Match phrases are short: "Possible match — plate not visible", "Found it", "Plate confirmed — {plate}" / "Got it".

### Detection Haptic Instead of New-Car Earcon — Current
- Superseded: earcon plus haptic tap on every new car (removed `80768cf`, 2026-09-04).
- Current (`529c42f`, `cf42049`, 2026-09-06): one light haptic per candidate after 0.3 s of continuously fresh boxes, at least 0.5 s apart, pre-match only, `enableHaptics` only. The stability gate filters YOLO flicker; the timer resets when a box goes stale.

### Beeps = Centering, Haptics = Distance — Current
**File:** `HapticBeepController.swift`
- Beep rate tracks horizontal centering. Haptic pulse rate tracks depth distance, with a steady 6 s pulse when depth is unavailable. Two channels give two independent cues.

### Connectivity Warnings Ungated by Category Toggles — Current (`36d31c2`, 2026-09-04)
- Offline / restored / weak-signal announcements respect only the master speech/haptics switches; they are safety-relevant.

### Lost Target Compass Threshold (60°) — Current
**File:** `MatchStatusSpeech.swift`

- Announce "car was last seen N degrees to the left/right" only when the heading delta since the car was last seen exceeds 60°; N is rounded to 30°.
- Too small (about 20°) interrupts as the user naturally moves; too large (about 120°) never helps. Announced once per lost transition to avoid bouncing between adjacent buckets.

---

## Candidate States

### Match Status: `.full` vs `.lost` — Current (clarified)
**File:** `Core/Candidate.swift`

- `.full`: verified match. Stays `.full` through occlusion until `missCount` reaches 90.
- `.lost`: was `.full`; no YOLO detection has overlapped it (IoU > 0.1) for 90 frames. The trigger is detection overlap, not Vision tracker failure.
- `.lost` candidates are not removed by the lifecycle service. They disappear when a new `.full` triggers `pruneToSingleMatched`, or on pipeline rebuild.
- `isMatched` is true only for `.full`. Navigation targeting treats `.partial` as navigable when `allowPartialNavigation` is on.

---

## Architecture Decisions

### Dependency Injection via AppContainer — Current
**File:** `AppContainer.swift`

- `AppContainer.shared.makePipeline(classes:description:isParatransitMode:settings:)` is the composition root: it builds `DetectionManager` (YOLO11n), `TrackingManager`, `DriftRepairService`, `VerifierService` (with `VerificationConfig` and strategy), `FrameNavigationManager` (with `Speaker`), `CandidateLifecycleService` and `FramePipelineCoordinator`.
- Every service is behind a protocol (`ObjectDetector`, `VisionTracker`, `DriftRepairServiceProtocol`, `VerifierServiceProtocol`, `NavigationSpeaker`, `CandidateLifecycleServiceProtocol`, `SpeechOutput`, `Beeper`, `HapticManagerProtocol`, `NetworkMonitorProtocol`, `APIHealthMonitorProtocol`, `CompassProvider`), so tests inject mocks directly into constructors.
- "Double Check" in `ContentView` rebuilds the whole pipeline (new `detectorKey`) instead of resetting individual services.

### CandidateStore Main-Thread Synchronization — Current
**File:** `Core/CandidateStore.swift`

- `candidates` is `@Published` for SwiftUI, so all writes and `snapshot()` hop to main with `DispatchQueue.main.sync` (direct call if already on main).
- Rationale: frames arrive on capture queues; a single serialization point avoids data races without locks.
- Caveats: `containsDuplicateOf`, `hasActiveMatch`, the subscript getter and the read at the top of `pruneToSingleMatched` read `candidates` without the hop. If the main thread ever blocks waiting on the frame-processing queue, the `main.sync` hop deadlocks; also, each mutation is a separate main-thread hop, so heavy per-frame mutation adds main-thread load.

### Single Winner Invariant — Current
**File:** `CandidateStore.pruneToSingleMatched()`, called by `CandidateLifecycleService.tick` every frame

- At most one `.full` candidate. When any `.full` exists, the most recently updated one is kept and all other candidates (including `.unknown`, `.partial`, `.rejected`, `.lost`) are removed. Ingest then stays off while it is `.full`.
- Rationale: users get into one rideshare; multiple simultaneous targets is unsupported.

### Batched Depth Sampling — Current (`9ea9514`, 2026-09-06; ARKit fix `9708b3b`)
**Files:** `FramePublishers/FramePublisher.swift`, `FramePipelineCoordinator.swift`

- `FrameProviderDelegate.processFrame` passes `depthAt: ([CGPoint]) -> [Float?]` (one result per point, same order) instead of a single-point lookup.
- The coordinator samples 5 points in the target box (center and ±25% on each axis) and uses the median valid depth. The center often hits a window gap or background.
- One call per frame amortizes depth-map lock/convert (AVFoundation) and keeps raycasts against the current frame/camera transform (ARKit).
- Coordinates: AVFoundation/video file get normalized image points; ARKit gets preview-view points (orientation + aspect-fill), because `makeRaycastQuery(from:)` expects view coordinates. `FramePipelineCoordinatorTests` covers this.
- `DepthProvider` in `PipelineProtocols.swift` is an older single-point protocol not used by the frame path.

### Capture Sources as FrameProviders — Current
**Files:** `FramePublishers/*`, `Views/CameraPreviewView.swift`

| Source | Class | Status |
| ------ | ----- | ------ |
| `.avFoundation` | `VideoCapture` | Default. Prefers LiDAR depth camera, then triple/dual/wide. |
| `.arKit` | `ARVideoCapture` | When `settings.useARMode`; UI toggle currently commented out. |
| `.videoFile` | `VideoFileFrameProvider` | Development/testing; no depth. |
| `.metaGlasses` | `MetaGlassesFrameProvider` | **Disabled.** The whole file and its factory case are commented out for App Store submission (`f60d50e`, 2026-04-04), because the Meta DAT SDK requires Bluetooth permissions. Design: a thin adapter polling `StreamSessionViewModel` at about 30 fps, orientation `.up`, no depth. |

### ARKit Usage — Current
**File:** `ARVideoCapture.swift`

- Current use: depth via raycasting (`.estimatedPlane`). Not the default mode.
- Spatial audio and AR anchors are possibilities but not implemented.
- `Settings.recommendedMode` returns `.avFoundation` with LiDAR and `.arKit` without, but nothing in the UI currently uses it.

### Localization — Current (`7c3f933`)
- All spoken phrases use `String(localized:)` / `NSLocalizedString`; English and Spanish. `Speaker` picks the voice from `settings.appLanguage`. Distance milestones use `MeasurementFormatter` (locale units; may mix languages).

---

## API Key Security

### Provider Keys Behind a Cloudflare Worker Proxy — Current (2026-10-28, PR #40)
**Files:** `proxy/`, `Utilities/Networking/APIProxy.swift`

**Problem.** The OpenAI and TrafficEye keys were build settings expanded into `Info.plist`, so every shipped build carried them in plain text. Keeping `Secrets.xcconfig` out of git doesn't help: Xcode copies the values into the compiled app. The OpenAI key kept leaking and its credits were drained. Separately, an older key was committed in `396af64` (2025-03) to this public repo. It is off all branches now but GitHub still serves the commit by hash.

**Threat model.** Automated scrapers that unzip public app builds, search for known provider key formats (OpenAI's `sk-…`), and use or resell any that work. The user base is a few thousand people, and there's no sign of anyone targeting CurbToCar specifically. The goal is to make a build worthless to a key scraper, not to stop a determined attacker aimed at this app.

**Decision.** The app ships no provider keys. Verifier requests go to a Cloudflare Worker that holds the keys as Worker secrets and forwards to OpenAI and TrafficEye. The app sends only `X-App-Token` (a random 64-hex-character token) and a per-install `X-Device-Id`.

The Worker limits what that token can do:
- Two routes only: `POST /v1/chat/completions` and `POST /recognition`. Everything else is a 404.
- Model allowlist (`gpt-6-luna`), `max_completion_tokens` capped at 300, and `n`/`stream`/`max_tokens` stripped.
- Body size caps: 4 MB chat, 5 MB image.
- 150 requests per 10 s per device ID and 600 per 10 s per IP.

  These are sized from the app's real request rate, which is far below the 30 fps frame rate. `VerifierService` sends at most one batch per second (`minVerifyInterval`), and only for `.unknown` candidates. A request moves the candidate to `.waiting`, so each car has at most one verification in flight. A retry waits at least 0.8 s after the last result (`perCandidateMMRInterval`). There are at most 10 candidates, and each verification makes up to 2 API calls. One car retrying is about 40 calls/min. Ten cars retrying at a busy curb is about 7 calls/s, with a first-batch burst of 10–20 calls in about 2 s. The device limit is about 2× that. The IP limit allows for several users behind one carrier IP. The first limits (60/min per device, 120/min per IP) would have stalled verification at a busy pickup. A 429 becomes a retryable `.apiError`, so it never causes a false match, but the user gets no feedback while it stalls. Spend is negligible at this scale, so the limits cap abuse rather than cost.

The OpenAI key is a service-account key in its own project, restricted to Chat Completions, with a project budget cap. That cap is the final limit on spend whatever happens upstream.

**Why this is enough for now.** A scraper finds no provider key in the build. The app token matches no known key format and only works against this proxy, under the limits above. Even someone who extracts the token by hand can spend at most what the rate limits and the budget cap allow.

**Why Cloudflare Workers.** There's no cold start (isolates, not containers), and it runs at the edge closest to the user. Measured overhead is roughly 20–60 ms on calls that already take 1–3 s. Hosts with cold starts (Lambda, Cloud Run) would add 0.3–10 s to the first verification of most sessions, because usage comes in bursts.

**Remaining risk.** The app token can be extracted from a build. That's acceptable under the threat model above. If it gets abused, rotate it (`wrangler secret put APP_TOKEN`, then ship a build with the new value) and move to App Attest (below).

**Rollout.** See `proxy/README.md` → Rollout for the steps, including retiring the old key.

### App Attest — Deferred (planned as the next phase)
App Attest would replace the extractable app token with per-install proof that a request comes from the genuine app on a real Apple device. The Secure Enclave generates a key, Apple attests it once per install, and the app signs every request. The proxy verifies the signature and a counter that must always increase.

It was deferred on 2026-10-28 because the proxy already defeats key scraping, which is the observed threat. Do it if Worker traffic stops looking like real users: sustained high volume from a few device IDs, round-the-clock use, or the OpenAI budget cap getting hit.

When it's picked up:
- **Roll out in soft mode first.** Unattested requests still pass with stricter limits and get logged. Turn on rejection once nearly all active users are on an attesting build. The Simulator, a few devices, and every build released before App Attest can't attest, so rejecting them on day one would stop car verification for those users.
- **Store the per-key counter in a Durable Object,** not KV. The counter check needs strongly consistent storage, and KV can briefly return stale values.
- **Use a vetted library for attestation verification** (Apple's certificate chain and CBOR). Hand-written X.509 chain validation is where security bugs hide.
- **App setup:** the App Attest capability (entitlement `com.apple.developer.devicecheck.appattest-environment`: `development` for Debug, `production` for Release). Users get no permission prompt, and the App Store privacy labels don't change.

---

## Tuning Guidelines

When adjusting thresholds, consider:

1. **Battery impact** – more frequent operations drain battery faster.
2. **Latency** – users need responsive feedback.
3. **Accuracy** – false positives/negatives affect trust.
4. **Interruption frequency** – too many announcements annoy users; check the shared cooldowns in `NavigationBehavior.md`.

Most thresholds were tuned empirically on real devices. When in doubt, test on hardware with representative usage. Update this file and the Quick Reference table when a value changes.
