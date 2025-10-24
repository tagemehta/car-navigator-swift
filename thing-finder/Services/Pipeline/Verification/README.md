# Verification Pipeline – Strategy-Driven TrafficEye ↔︎ LLM Loop

> _Updated 2025-10-23 to document the new **strategy-manager architecture**._

This document describes how the verification subsystem combines the paid, low-latency **TrafficEye MMR API** with the slower but cheaper **LLM-based verifier**.  
A **strategy manager** picks the best engine for every frame, guided by policy counters and configurable thresholds.

---

## 1  High-Level Architecture

```
+------------------+            +-------------------------+
|  VerifierService |  creates   | VerificationStrategyFactory |
+---------+--------+            +---------------+---------+
          |                                     |
          |  produces                  +--------v---------+
          |                            | Strategy Manager |
          |                            +--------+---------+
          |                                     |
   calls  |  verify(image,candidate,store)      | selects best strategy
          |                                     v
          |                            +------------------+
          |                            |  Strategies[]    |  (TrafficEye, LLM, …)
          |                            +--------+---------+
          |                                     |
          +-------------------------------------+
                         performVerification()
```

* **VerifierService** – public entry-point. Runs on every tracking _tick_ and owns global throttling.
* **VerificationStrategyFactory** – builds all available strategies once at startup.
* **Strategy Manager** – runtime decision maker. For each candidate:
  * Filters strategies via `shouldUse(for:)`.
  * Picks highest `priority(for:)`.
  * Resets the *other* engine’s counters before execution.
* **Concrete Strategies** – wrapper classes (`TrafficEyeStrategy`, `LLMStrategy`, `AdvancedLLMStrategy`) that delegate to the underlying verifiers while honouring timeouts and error handling in `BaseVerificationStrategy`.

---

## 2  Engines

| Engine | Typical Latency | Relative Cost | Strengths |
|--------|-----------------|--------------|-----------|
| **TrafficEye MMR API** | ≈ 50 ms | $$$ | Precise make-model, reliable front / rear discrimination. |
| **LLM Verifier** | 3-10 s | $ | Robust to partial / side views; fuzzy semantic reasoning. |

---

## 3  Escalation Policy (`VerificationPolicy`)

```
TrafficEye failures ≥ 3
          │
          ▼
     choose LLM
          │
          ▼
LLM failures ≥ 3
          │
          ▼
 choose TrafficEye
```

* **TrafficEye first.** After **three** consecutive failures for the same candidate, escalate to LLM.
* **LLM fallback.** After **three** consecutive LLM failures, fall back to TrafficEye.
* **Counters reset.** Switching engines zeroes the opposite counter so the loop can repeat until match or hard-reject.

_Tunable constants_: `maxPrimaryRetries` (TrafficEye → LLM) and `maxLLMRetries` (LLM → TrafficEye).

---

## 4  Per-Frame Flow (`VerifierService.tick()`)

1. Snapshot all `Candidate`s.
2. Skip verification if global throttle `minVerifyInterval` (1 s) has not elapsed.
3. For every candidate due:
   1. Ask **Strategy Manager** to `verify (image,candidate,store)`.
   2. Manager selects best strategy (section 1) and resets counters.
   3. Strategy runs `performVerification`, returns a `VerificationOutcome`.
   4. On failure the manager increments the relevant attempt counter.
   5. Outcomes propagate to `CandidateStore` (status, description, timings).

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

| Area | Key File (link) | What Happens |
|------|-----------------|--------------|
| **Frame Tick** | `VerifierService.swift` (`tick(...)`) | Called every video frame; snapshots candidate store, applies global throttle (1c) and triggers verification/OCR. |
| **Candidate Filtering** | `VerifierService.swift` (1b) | Filters unknown candidates before verification. |
| **Batch Throttling** | `VerifierService.swift` (1c) | Ensures at least 1 s between verify batches via `lastVerifyBatch`. |
| **Strategy Delegation** | `VerifierService.swift` (1d) | Sends image + candidate to Strategy Manager. |
| **Strategy Manager** | `VerificationStrategy.swift` (2a–2c) | Selects best strategy, resets opposite counter, increments counters on failure. |
| **TrafficEye Strategy** | `TrafficEyeStrategy.swift` (2d, 3d) | Fast path; blocks when attempt limit reached. |
| **TrafficEye Verifier** | `TrafficEyeVerifier.swift` (3a–3e) | Blur check → API call → early plate match → LLM fallback. |
| **LLM / Advanced Strategies** | `LLMStrategy.swift`, `AdvancedLLMStrategy.swift` | Secondary / fallback semantic verification paths. |
| **OCR Pipeline** | `VerifierService.swift` (4a…) | Optional license-plate OCR for partial matches with retry caps. |

---

## 8  Future Work

* Multi-frame voting (require N agreeing positives within T seconds).
* Adaptive timing based on real-world cost data.
* Smarter side-view heuristics leveraging `VehicleView` once TrafficEye side-view accuracy improves further.

---
_Last updated: 2025-10-23_
