# Verification Pipeline – Strategy-Based Verifier Selection

> _Updated 2026-03-06 after **strategy enum refactor** – added configurable verifier selection._

This document describes how the verification subsystem selects between **TrafficEye MMR API** (hybrid: TrafficEye + OpenAI comparison), **TwoStepVerifier** (pure LLM), and **AdvancedLLMVerifier** (paratransit/custom features).  
A **VerifierSelector** picks the engine based on `VerificationConfig.strategy` and attempt counters.

---

## 1  High-Level Architecture (Simplified)

```
+------------------+
|  VerifierService |  (orchestration, throttling, cropping)
+---------+--------+
          |
          | verify(image, candidate, store)
          v
+---------+--------+
| VerifierSelector |  (selection, counter-reset, timeout)
+---------+--------+
          |
          | delegates to verifiers based on strategy
          v
+------------------+------------------+------------------+
| TrafficEyeVerifier | TwoStepVerifier | AdvancedLLMVerifier |
|    (hybrid)        |     (LLM)       |   (paratransit)     |
+--------------------+-----------------+---------------------+
```

**2-Layer Design:**
* **VerifierService** – Frame-driven orchestrator. Runs on every tracking tick, handles global throttling, crops images, updates `CandidateStore` with results.
* **VerifierSelector** – Selection logic. Uses `VerificationConfig.strategy` to determine which verifier(s) to use, handles escalation (hybrid mode), resets counters, applies timeout, converts errors to outcomes.

**Strategy-based selection** – `VerifierStrategy` enum (`.hybrid`, `.llmOnly`, `.trafficEyeOnly`) determines which verifiers are instantiated and used.

---

## 2  Engines

| Engine | Typical Latency | Relative Cost | Strengths |
|--------|-----------------|--------------|-----------|
| **TrafficEyeVerifier** (hybrid) | ≈ 1.9s | $$$ | TrafficEye API for make/model/color + OpenAI for semantic comparison. Robust to side views (as of 10/23). |
| **TwoStepVerifier** (LLM) | 4-5s | $ | Pure LLM fallback. Robust to partial/side views; fuzzy semantic reasoning. |
| **AdvancedLLMVerifier** (LLM) | 4-5s | $ | Combined extraction + matching in single LLM call. For paratransit (wheelchair lifts, ramps) and custom features. |

---

## 3  Verifier Strategies

### `.hybrid` (default for car search)
```
TrafficEye failures ≥ 3
          │
          ▼
   choose TwoStepVerifier
          │
          ▼
LLM failures ≥ 3
          │
          ▼
 choose TrafficEye
```
* **TrafficEye first.** After **three** consecutive failures, escalate to TwoStepVerifier.
* **LLM fallback.** After **three** consecutive LLM failures, fall back to TrafficEye.
* **Counters reset.** Switching engines zeroes the opposite counter so the loop can repeat until match or hard-reject.

### `.llmOnly` (paratransit, custom features)
* Always uses **AdvancedLLMVerifier**
* No TrafficEye calls (saves API costs)
* No escalation loop (single verifier)

### `.trafficEyeOnly` (simple MMR-only)
* Always uses **TrafficEyeVerifier**
* No LLM fallback
* Faster, cheaper for cases where TrafficEye alone is sufficient

---

## 4  Per-Frame Flow (`VerifierService.tick()`)

1. Snapshot all `Candidate`s from the store.
2. Skip verification if global throttle `minVerifyInterval` (1 s) has not elapsed.
3. For every candidate due:
   1. Crop the candidate image from the pixel buffer.
   2. Ask **VerifierSelector** to `verify(image, candidate, store)`.
   3. Selector uses `selectVerifier(for: candidate)` to pick based on strategy:
      - `.hybrid`: TrafficEye or TwoStepVerifier based on attempt counters
      - `.llmOnly`: Always AdvancedLLMVerifier
      - `.trafficEyeOnly`: Always TrafficEyeVerifier
   4. Selector resets the opposite counter (hybrid mode only).
   5. Selector calls the chosen verifier, applies 10s timeout, converts errors to outcomes.
   6. On failure, `VerifierService` increments the relevant attempt counter.
   7. Outcomes propagate to `CandidateStore` (status, description, timings).

---

## 5  Counters & Runtime Data

| Field | Purpose |
|-------|---------|
| `trafficAttempts` | Consecutive failed TrafficEye calls. |
| `llmAttempts` | Consecutive failed LLM calls. |
| `VehicleView` / `viewScore` | Best observed angle – still informative for analytics and future heuristics. |
| `lastMMRTime` | Timestamp of the last TrafficEye call for this candidate (per-candidate throttle). |

---

## 6  Throttling

* **Global** – `minVerifyInterval` (3 s) prevents frame-rate MMR floods.
* **Per Candidate** – `perCandidateMMRInterval` (0.8 s) caps paid hits per vehicle.

Together these rules ensure:
* Every car incurs **≥ 1** TrafficEye call (needed to classify view).
* Additional TrafficEye calls are rare; LLM calls are rarer still.
* Users get instant feedback for clear angles, and slower but acceptable feedback otherwise.

---

## 7  Implementation Highlights

| Area | Key File | What Happens |
|------|----------|--------------|
| **Frame Tick** | `VerifierService.swift` | Called every video frame; snapshots candidate store, applies global throttle and triggers verification/OCR. |
| **Candidate Filtering** | `VerifierService.swift` | Filters unknown candidates before verification. |
| **Batch Throttling** | `VerifierService.swift` | Ensures at least 1 s between verify batches via `lastVerifyBatch`. |
| **Image Cropping** | `VerifierService.swift` | Crops candidate bounding box from pixel buffer before verification. |
| **Verifier Selection** | `VerifierSelector.swift` | Uses `strategy` to pick verifier, handles escalation (hybrid mode), resets counters. |
| **Strategy Config** | `VerificationConfig.swift` | Defines `VerifierStrategy` enum (`.hybrid`, `.llmOnly`, `.trafficEyeOnly`). |
| **TrafficEye Verifier** | `TrafficEyeVerifier.swift` | Hybrid: TrafficEye API for make/model/color → OpenAI for semantic comparison. |
| **TwoStep Verifier** | `TwoStepVerifier.swift` | Pure LLM fallback: extract vehicle info → compare to target description. |
| **Advanced LLM Verifier** | `AdvancedLLMVerifier.swift` | Combined extraction + matching for paratransit and custom features. |
| **Counter Management** | `VerifierService.swift` | Increments `trafficAttempts` or `llmAttempts` on failure. |
| **OCR Pipeline** | `VerifierService.swift` | Optional license-plate OCR for partial matches with retry caps. |

---

## 8  Future Work

* Multi-frame voting (require N agreeing positives within T seconds).
* Adaptive timing based on real-world cost data.
* Smarter side-view heuristics leveraging `VehicleView` once TrafficEye side-view accuracy improves further.

---
_Last updated: 2026-03-06 (added strategy-based verifier selection, merged VerificationPolicy into VerifierSelector)_
