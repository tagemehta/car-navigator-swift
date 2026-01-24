# Design Decisions & Tuning Rationale

This document explains the reasoning behind key thresholds and architectural choices in Thing Finder.

---

## Pipeline Thresholds

### Drift Repair Stride (15 frames)
**File:** `DriftRepairService.swift`

- **Value:** Every 15 frames (~0.5s at 30fps)
- **Tradeoff:** Battery/lag vs accuracy
- **Rationale:** Empirically tuned to balance:
  - Lower values = more accurate tracking but higher CPU/battery drain
  - Higher values = better performance but more drift accumulation
  - 15 frames provides good accuracy without noticeable lag

### Embedding Similarity Threshold (0.90)
**File:** `DriftRepairService.swift`

- **Value:** 0.90 cosine similarity
- **Rationale:** Somewhat arbitrarily chosen. High enough to avoid false re-associations, low enough to handle minor appearance changes between frames.

### Miss Threshold (15 frames)
**File:** `CandidateLifecycleService.swift`

- **Value:** 15 consecutive frames without detection overlap
- **Rationale:** At 30fps, this is ~0.5 seconds. Provides reasonable tolerance for:
  - Brief occlusions
  - Detection flickering
  - Fast camera movements

### Duplicate Detection (IoU > 0.6, center distance < 0.15)
**File:** `CandidateStore.swift`

- **Values:** IoU threshold 0.6, center distance 0.15 (normalized)
- **Rationale:** Empirically tuned to prevent creating duplicate candidates for the same object while still allowing nearby distinct objects.

---

## Verification System

### Escalation Thresholds
**File:** `VerificationPolicy.swift`

| Engine | Fail Threshold | Action |
|--------|----------------|--------|
| TrafficEye | 1 fail | Try side view |
| TrafficEye | 3 fails | Escalate to LLM |
| LLM | 2 fails | Back to TrafficEye |

**Rationale:** Arbitrarily chosen based on latency characteristics:
- TrafficEye: ~1.9s per call (fast, can retry more)
- LLM: ~4-5s per call (slow, fewer retries before switching)

The system loops indefinitely between engines until match or hard reject.

### OCR Retry Limit (30 attempts)
**File:** `VerificationConfig.swift`

- **Value:** 30 attempts
- **Status:** ⚠️ **LEGACY** – This high limit was originally needed because OCR might be off by a single character. Now that Levenshtein distance matching is implemented (`maxEditsForMatch: 1`), fuzzy matching handles minor OCR errors automatically.
- **Note:** This value could be reduced significantly in a future cleanup.

---

## Navigation Feedback

### Lost Target Compass Threshold (60°)
**File:** `MatchStatusSpeech.swift`

- **Value:** Only announce compass direction if angle > 60°
- **Rationale:** Balances information vs interruption:
  - Too small (e.g., 20°) = frequent interruptions as user naturally moves
  - Too large (e.g., 120°) = user never gets helpful directional info
  - 60° represents a significant change worth announcing

---

## Candidate States

### Match Status: `.full` vs `.lost`
**File:** `Candidate.swift`

- **`.full`** = Active match with valid bounding box in current frame
- **`.lost`** = Was previously `.full` but no longer have a box for this candidate

**Key distinction:** A candidate stays `.full` as long as we're actively tracking it, even if temporarily occluded. It only becomes `.lost` when tracking fails completely (missCount exceeds threshold).

---

## Architecture Decisions

### Single Winner Invariant
**File:** `CandidateStore.pruneToSingleMatched()`

- **Behavior:** At most one candidate can be `.full` at a time
- **Rationale:** Users get into one rideshare, not multiple. Multiple simultaneous targets is not a supported use case.

### ARKit Usage
**File:** `ARVideoCapture.swift`

- **Current use:** Depth data via raycasting
- **Future potential:** Spatial audio and AR anchors exist as possibilities but are not currently implemented. ARKit integration provides the foundation if needed.

---

## Tuning Guidelines

When adjusting thresholds, consider:

1. **Battery impact** – More frequent operations drain battery faster
2. **Latency** – Users need responsive feedback
3. **Accuracy** – False positives/negatives affect trust
4. **Interruption frequency** – Too many announcements annoy users

Most thresholds were empirically tuned on real devices. When in doubt, test on hardware with representative usage patterns.
