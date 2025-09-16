# Verification Pipeline – Continuous TrafficEye ↔︎ LLM Loop

> _Updated 2025-08-06 for the new cycling policy_

This document explains how the **hybrid verifier** balances cost, latency and accuracy by **cycling indefinitely** between the paid but fast **TrafficEye MMR API** and the slower yet cheaper **LLM-based verifier** until a conclusive decision is reached.

---

## 1  Engines

| Engine | Typical Latency | Relative Cost | When We Prefer It |
|--------|-----------------|--------------|-------------------|
| **TrafficEye MMR** | ≈ 50 ms | $$$ | Precise make-model; reliable front / rear discrimination. |
| **LLM Verifier**   | 3-10 s | $   | Robust to partial / side views; fuzzy semantic reasoning. |

## 2  Escalation Logic (implemented in `VerificationPolicy`)
```
side-view                    any view
   ─────────────────────┐   ┌─────────────────────────────
TrafficEye failures ≥ 1 ─┘   │ TrafficEye failures ≥ 3     │
                            ▼                             ▼
                      choose LLM                   choose LLM
                           ▲                             │
                LLM failures ≥ 2 ────────────────────────┘
```
1. **TrafficEye first.** After 1 failure on a side view, or 3 failures on any view, escalate to LLM.
2. **LLM fallback.** After 2 consecutive LLM failures, fall back to TrafficEye.
3. **Counters reset.** Each time we switch engine the opposite counter is reset, allowing the loop to repeat endlessly until a match or hard-reject.

> Constants (`minPrimaryRetries`, `maxPrimaryRetries`, `maxLLMRetries`) are tunable without touching the service.

## 3  Per-Frame Flow (`VerifierService.tick()`)
1. Snapshot all `Candidate`s.
2. Skip if global throttle (`minVerifyInterval`) not elapsed.
3. For each candidate due for verification:
   1. Call `VerificationPolicy.nextKind` → **TrafficEye or LLM**.
   2. **Reset** the opposite counter inside `VerifierService`.
   3. Crop, encode and send the image to the chosen verifier (async).
   4. Update `CandidateStore`:
      * On success → `.matched` (+timings, description).
      * On failure → increment active counter, remain `.unknown` unless hard reject.
4. Optionally enqueue OCR when a partial match requires a plate check.

## 4  Counters & Data Fields
| Field | Purpose |
|-------|---------|
| `trafficAttempts` | Consecutive failed TrafficEye calls. |
| `llmAttempts` | Consecutive failed LLM calls. |
| `VehicleView` + `viewScore` | Best observed angle assists early side-view escalation. |
| `lastMMRTime` | Candidate-level TrafficEye throttle. |

## 5  Throttling
* **Global** – `minVerifyInterval` (1 s) to keep API usage sane.
* **Per-candidate** – implicit via counters + `lastMMRTime`.

## 6  Why Loop?
• Vehicles may enter/exist the frame at awkward angles; continuous cycling ensures we keep trying the cheaper, faster path whenever it might now succeed.

• Eliminates sticky failure states where a candidate could rack up counters and get stuck on the slow path for the remainder of its lifetime.

---
_Last updated: 2025-08-06_

This document describes the **view-aware, cost-aware vehicle verification pipeline** introduced in August 2025.

## Overview
The system combines two verification engines:

| Engine | Latency | Cost | Strengths |
|--------|---------|------|-----------|
| **TrafficEye MMR API** | ~50 ms | High | Precise make-model-rear/front detection. Provides *view angle* metadata. |
| **LLM Verifier** | 3-10 s | Low | Handles side/partial views; good at fuzzy semantic reasoning. |

Goal: maximise accuracy while *minimising paid MMR calls* and *avoiding LLM latency* whenever a clean front/rear shot is available.

## Key Data Added
* `Candidate.VehicleView` – `.front`, `.rear`, `.side`, `.unknown`  
  stores the **best observed angle** + `viewScore`.
* `lastMMRTime` – last timestamp this candidate hit the MMR API.
* `waitingUntil` – when a side/unknown view may fall back to LLM.
* `VerificationConfig`
  * `perCandidateMMRInterval` (default 2 s)
  * `sideViewWait` (default 0.8 s)

## Processing Steps
1. **Initial detection**  
   *Every new candidate* immediately triggers **one** MMR call, giving both
   – a quick match decision, and  
   – the first `vehicleView` assessment.

2. **Fast path** – *front / rear*  
   If that angle is `.front` or `.rear`:
   * Accept / reject using the **MMR result only**.  
   * Do **not** call the LLM.  
   * Further MMR calls for this candidate are suppressed for
     `perCandidateMMRInterval` seconds.

3. **Slow path** – *side / unknown*
   * Set `waitingUntil = now + sideViewWait`.
   * Delay and keep scanning frames.
   * When the per-candidate MMR throttle expires:
     * If a *new* MMR returns front/rear → go to Fast path.
     * Else if `now ≥ waitingUntil` → fire **one** LLM call and cache its result.  
       (LLM results are cheap but slow; we only pay when truly necessary.)

4. **Book-keeping after every verification**
   * `updateView()` keeps the best angle and score.
   * `lastMMRTime` stamped for MMR responses.
   * `waitingUntil` reset/cleared as appropriate.

## Throttling Summary
* **Global** – `minVerifyInterval` (3 s) prevents frame-rate MMR floods.
* **Per Candidate** – `perCandidateMMRInterval` (2 s) caps paid hits per car.
* **Side-view Timeout** – `sideViewWait` (0.8 s) before allowing an LLM fallback.

Together these rules mean:
* Every car costs **≥1** MMR call (cannot know angle otherwise).
* Subsequent MMR calls are rare, LLM calls are rarer.
* User receives quick confirmation for good angles; slower but still timely feedback when only side views are visible.

## Future Enhancements
* **Multi-frame vote** – require 2 agreeing positives within 1 s before full match.
* Adaptive timing based on real-world cost data.
* Dynamic change of `sideViewWait` if vehicle remains side-only for extended periods.

---
_Last updated: 2025-08-01_
