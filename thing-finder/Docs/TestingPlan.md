# Thing Finder Testing Plan

## Overview

Comprehensive testing strategy for Thing Finder, starting from scratch. Prioritizes **testability**, **isolation**, and **determinism** for reliable CI/CD.

---

## Testing Layers

| Layer | Scope | Tools | Frequency |
|-------|-------|-------|-----------|
| **Unit** | Single class/function | XCTest + mocks | Every commit |
| **Integration** | Multiple services | XCTest + real deps | PR merge |
| **Snapshot** | UI consistency | XCTest + snapshots | Weekly |
| **Manual** | End-to-end | Human tester | Release |

---

## 1. Core Domain Tests

### 1.1 `Candidate` Tests
**File:** `CandidateTests.swift`

| Test Case | Description |
|-----------|-------------|
| `test_init_setsDefaultValues` | New candidate has `.unknown` status, zero missCount, nil embedding |
| `test_updateView_tracksMaxScore` | `updateView()` only updates if new score > existing |
| `test_isMatched_returnsTrueForFullAndPartial` | `.full` and `.partial` return true, others false |
| `test_verificationTracker_countersIncrementCorrectly` | Traffic/LLM attempt counters work independently |

### 1.2 `CandidateStore` Tests
**File:** `CandidateStoreTests.swift`

| Test Case | Description |
|-----------|-------------|
| `test_upsert_createsNewCandidate` | First detection creates candidate |
| `test_upsert_rejectsDuplicate` | Detection with IoU > 0.6 to existing is rejected |
| `test_update_mutatesCandidateInPlace` | Closure-based update modifies correct candidate |
| `test_remove_deletesCandidate` | Candidate removed from store |
| `test_snapshot_returnsImmutableCopy` | Mutations to snapshot don't affect store |
| `test_hasActiveMatch_detectsFullOrPartial` | Returns true when any candidate is matched |
| `test_pruneToSingleMatched_keepsOnlyLatest` | Multiple matched → only most recent survives |
| `test_threadSafety_concurrentUpdates` | Dispatch 100 updates from background queues, no crashes |

### 1.3 `DetectionStateMachine` Tests
**File:** `DetectionStateMachineTests.swift`

| Test Case | Description |
|-----------|-------------|
| `test_emptyStore_returnsSearching` | No candidates → `.searching` |
| `test_unknownCandidates_returnsSearching` | All `.unknown` → `.searching` |
| `test_waitingCandidates_returnsVerifying` | Any `.waiting` → `.verifying(ids:)` |
| `test_fullCandidate_returnsFound` | Any `.full` → `.found(id:)` |
| `test_priorityOrder_foundBeatsVerifying` | `.full` takes precedence over `.waiting` |

---

## 2. Pipeline Service Tests

### 2.1 `DetectionManager` Tests
**File:** `DetectionManagerTests.swift`

**Requires:** Mock `VNCoreMLModel` or pre-recorded detection results

| Test Case | Description |
|-----------|-------------|
| `test_detect_filtersToTargetClasses` | Only returns detections matching target classes |
| `test_stableDetections_requiresConsecutiveFrames` | Detection must appear N frames before returned |
| `test_detect_handlesEmptyFrame` | No crash on frame with zero detections |

### 2.2 `TrackingManager` Tests
**File:** `TrackingManagerTests.swift`

**Requires:** Mock `VNSequenceRequestHandler`

| Test Case | Description |
|-----------|-------------|
| `test_tick_updatesExistingCandidateBoundingBox` | Tracked candidate's bbox changes |
| `test_tick_removesLostTracking` | Tracking request marked finished → candidate updated |
| `test_tick_handlesEmptyStore` | No crash when store is empty |

### 2.3 `DriftRepairService` Tests
**File:** `DriftRepairServiceTests.swift`

**Requires:** Mock `ImageUtilities`, pre-computed embeddings

| Test Case | Description |
|-----------|-------------|
| `test_tick_skipsNonRepairFrames` | Only runs every N frames (default 15) |
| `test_tick_reassociatesBySimilarity` | Candidate with drifted bbox snaps to matching detection |
| `test_tick_marksUnmatchedForDestruction` | No matching detection → bbox set to .zero |
| `test_similarityThreshold_rejectsLowScores` | Similarity < 0.90 not matched |

### 2.4 `CandidateLifecycleService` Tests
**File:** `CandidateLifecycleServiceTests.swift`

| Test Case | Description |
|-----------|-------------|
| `test_tick_ingestsNewDetections` | Fresh detection creates candidate |
| `test_tick_skipsIngestWhenActiveMatch` | No new candidates when `.full` exists |
| `test_tick_incrementsMissCount` | Candidate not overlapping detection gets +1 |
| `test_tick_removesStaleCandidate` | missCount > threshold → removed |
| `test_tick_marksFullAsLost` | Matched candidate exceeds miss threshold → `.lost` |
| `test_tick_removesRejectedAfterCooldown` | Rejected candidate removed after N seconds |
| `test_tick_returnsLostFlag` | Returns true when matched candidate dropped |

---

## 3. Verification Tests

### 3.1 `VerificationStrategyManager` Tests
**File:** `VerificationStrategyManagerTests.swift`

**Requires:** Mock strategies

| Test Case | Description |
|-----------|-------------|
| `test_selectStrategy_choosesHighestPriority` | Strategy with max priority selected |
| `test_selectStrategy_filtersUnsuitableStrategies` | `shouldUse() == false` excluded |
| `test_verify_resetsOppositeCounter` | Switching to TrafficEye resets LLM counter |
| `test_verify_returnsNoSuitableStrategyError` | All strategies unsuitable → error |

### 3.2 `TrafficEyeVerifier` Tests
**File:** `TrafficEyeVerifierTests.swift`

**Requires:** Mock URLSession, sample API responses

| Test Case | Description |
|-----------|-------------|
| `test_verify_rejectsBlurryImage` | blurScore > threshold → immediate reject |
| `test_verify_parsesMMRResponse` | Correct make/model/color extracted |
| `test_verify_handlesNetworkError` | Timeout/error → appropriate reject reason |
| `test_verify_extractsPlateText` | License plate from OCR field parsed |
| `test_verify_calculatesConfidence` | Score below threshold → ambiguous |

### 3.3 `TwoStepVerifier` Tests
**File:** `TwoStepVerifierTests.swift`

**Requires:** Mock URLSession, sample OpenAI responses

| Test Case | Description |
|-----------|-------------|
| `test_verify_extractsVehicleInfo` | First step extracts make/model/color |
| `test_verify_matchesDescription` | Second step confirms match |
| `test_verify_handlesOccludedVehicle` | Low visible_fraction → reject |
| `test_verify_handlesNoToolResponse` | Missing tool call → error |

### 3.4 `VerifierService` Tests
**File:** `VerifierServiceTests.swift`

**Requires:** Mock strategy manager, mock store

| Test Case | Description |
|-----------|-------------|
| `test_tick_skipsSmallBoundingBox` | bbox < 1% area skipped |
| `test_tick_skipsTallBoundingBox` | h/w > 3 skipped |
| `test_tick_rateLimitsVerification` | Respects minVerifyInterval |
| `test_tick_updatesMatchStatusOnSuccess` | Successful verify → `.full` or `.partial` |
| `test_tick_handlesRetryableReason` | Retryable reject → stays `.unknown` |
| `test_tick_handlesHardReject` | Non-retryable → `.rejected` |

### 3.5 OCR Tests
**File:** `OCREngineTests.swift`

| Test Case | Description |
|-----------|-------------|
| `test_recognizePlate_extractsText` | Valid plate image → text returned |
| `test_recognizePlate_filtersLowConfidence` | Below threshold → nil |
| `test_levenshteinDistance_calculatesCorrectly` | Edit distance matches expected |
| `test_plateMatching_allowsOneEdit` | 1 char difference → match |
| `test_plateMatching_rejectsTwoEdits` | 2+ char difference → reject |

---

## 4. Navigation Tests

### 4.1 `NavAnnouncer` Tests
**File:** `NavAnnouncerTests.swift`

**Requires:** Mock `SpeechOutput`

| Test Case | Description |
|-----------|-------------|
| `test_tick_speaksOnStatusTransition` | `.unknown` → `.full` triggers speech |
| `test_tick_suppressesRepeatPhrase` | Same phrase within cooldown not spoken |
| `test_tick_announcesRetryReason` | Retryable reject → retry phrase |
| `test_tick_respectsWaitingCooldown` | `.waiting` phrase throttled |

### 4.2 `HapticBeepController` Tests
**File:** `HapticBeepControllerTests.swift`

**Requires:** Mock `Beeper`

| Test Case | Description |
|-----------|-------------|
| `test_tick_startsBeepWhenTargetPresent` | Target box → beeper started |
| `test_tick_stopsBeepWhenTargetLost` | No target → beeper stopped |
| `test_tick_adjustsIntervalByCentering` | Centered target → shorter interval |
| `test_tick_respectsEnableBeepsSetting` | Disabled → no beeps |

### 4.3 `MatchStatusSpeech` Tests
**File:** `MatchStatusSpeechTests.swift`

| Test Case | Description |
|-----------|-------------|
| `test_phrase_fullWithPlate` | Returns "Found matching plate X" |
| `test_phrase_fullWithDescription` | Returns "Found [description]" |
| `test_phrase_rejected` | Includes reject reason |
| `test_phrase_lost` | Includes compass direction |
| `test_phrase_unknown` | Returns nil |

---

## 5. Utility Tests

### 5.1 `ImageUtilities` Tests
**File:** `ImageUtilitiesTests.swift`

| Test Case | Description |
|-----------|-------------|
| `test_inverseRotation_allOrientations` | Test each CGImagePropertyOrientation |
| `test_unscaledBoundingBoxes_correctPixelRect` | Normalized → pixel conversion accurate |
| `test_cvPixelBufferToCGImage_succeeds` | Valid buffer → CGImage |

### 5.2 `EmbeddingComputer` Tests
**File:** `EmbeddingComputerTests.swift`

| Test Case | Description |
|-----------|-------------|
| `test_compute_returnsFeaturePrint` | Valid image → non-nil observation |
| `test_compute_withBoundingBox_cropsThenEmbeds` | Cropped region embedded |
| `test_cosineSimilarity_identicalImages` | Same image → similarity ~1.0 |
| `test_cosineSimilarity_differentImages` | Different images → lower score |

### 5.3 `DescriptionParser` Tests
**File:** `DescriptionParserTests.swift`

| Test Case | Description |
|-----------|-------------|
| `test_extractPlate_findsValidPlate` | "Blue Honda ABC1234" → "ABC1234" |
| `test_extractPlate_requiresDigitAndLetter` | "12345678" → nil (no letter) |
| `test_extractPlate_removesFromRemainder` | Plate removed from description |
| `test_extractPlate_handlesNoPlate` | "Blue Honda Civic" → nil |

### 5.4 `CGRect+IoU` Tests
**File:** `CGRectIoUTests.swift`

| Test Case | Description |
|-----------|-------------|
| `test_iou_identicalRects` | Same rect → 1.0 |
| `test_iou_noOverlap` | Disjoint rects → 0.0 |
| `test_iou_partialOverlap` | 50% overlap → ~0.33 |

---

## 6. Integration Tests

### 6.1 `FramePipelineCoordinator` Integration
**File:** `FramePipelineCoordinatorIntegrationTests.swift`

**Setup:** Real services with mock camera frames

| Test Case | Description |
|-----------|-------------|
| `test_fullPipeline_detectsAndTracksObject` | Detection → tracking → candidate created |
| `test_fullPipeline_verifiesCandidate` | Candidate → verification → status update |
| `test_fullPipeline_handlesLostObject` | Object leaves frame → `.lost` status |
| `test_fullPipeline_publishesPresentation` | Each frame → `FramePresentation` published |

### 6.2 `AppContainer` Integration
**File:** `AppContainerIntegrationTests.swift`

| Test Case | Description |
|-----------|-------------|
| `test_makePipeline_wiresAllDependencies` | Pipeline has all services non-nil |
| `test_makePipeline_parsesPlateFromDescription` | Plate extracted and passed to verifier |

---

## 7. Mock Objects Required

### Protocols to Mock

| Protocol | Mock Name | Purpose |
|----------|-----------|---------|
| `ObjectDetector` | `MockDetector` | Return canned detections |
| `VisionTracker` | `MockTracker` | Simulate tracking updates |
| `VerifierServiceProtocol` | `MockVerifier` | Return canned verification results |
| `DriftRepairServiceProtocol` | `MockDriftRepair` | No-op or controlled behavior |
| `NavigationSpeaker` | `MockNavigationSpeaker` | Record tick calls |
| `SpeechOutput` | `MockSpeaker` | Record spoken phrases |
| `Beeper` | `MockBeeper` | Record start/stop calls |
| `CandidateLifecycleServiceProtocol` | `MockLifecycle` | Controlled candidate creation |
| `FrameProvider` | `MockFrameProvider` | Pump test frames |
| `OCREngine` | `MockOCREngine` | Return canned plate text |

### Test Fixtures

| Fixture | Description |
|---------|-------------|
| `TestPixelBuffers` | Pre-recorded CVPixelBuffers for detection |
| `TestDetections` | Array of `VNRecognizedObjectObservation` |
| `TestCandidates` | Pre-configured `Candidate` instances |
| `TestAPIResponses` | JSON for TrafficEye/OpenAI mocks |

---

## 8. Test File Organization

```
thing-finderTests/
├── Mocks/
│   ├── MockDetector.swift
│   ├── MockTracker.swift
│   ├── MockVerifier.swift
│   ├── MockSpeaker.swift
│   ├── MockBeeper.swift
│   ├── MockOCREngine.swift
│   └── MockFrameProvider.swift
├── Fixtures/
│   ├── TestPixelBuffers.swift
│   ├── TestDetections.swift
│   ├── TestCandidates.swift
│   └── TestAPIResponses.swift
├── Core/
│   ├── CandidateTests.swift
│   ├── CandidateStoreTests.swift
│   └── DetectionStateMachineTests.swift
├── Pipeline/
│   ├── DetectionManagerTests.swift
│   ├── TrackingManagerTests.swift
│   ├── DriftRepairServiceTests.swift
│   └── CandidateLifecycleServiceTests.swift
├── Verification/
│   ├── VerificationStrategyManagerTests.swift
│   ├── TrafficEyeVerifierTests.swift
│   ├── TwoStepVerifierTests.swift
│   ├── VerifierServiceTests.swift
│   └── OCREngineTests.swift
├── Navigation/
│   ├── NavAnnouncerTests.swift
│   ├── HapticBeepControllerTests.swift
│   └── MatchStatusSpeechTests.swift
├── Utilities/
│   ├── ImageUtilitiesTests.swift
│   ├── EmbeddingComputerTests.swift
│   ├── DescriptionParserTests.swift
│   └── CGRectIoUTests.swift
├── Integration/
│   ├── FramePipelineCoordinatorIntegrationTests.swift
│   └── AppContainerIntegrationTests.swift
└── thing-finderTests.xctestplan
```

---

## 9. Implementation Priority

### Phase 1: Foundation (Week 1)
1. Create all mock objects
2. `CandidateTests`
3. `CandidateStoreTests`
4. `DetectionStateMachineTests`
5. `DescriptionParserTests`
6. `CGRectIoUTests`

### Phase 2: Pipeline Services (Week 2)
1. `CandidateLifecycleServiceTests`
2. `DriftRepairServiceTests`
3. `TrackingManagerTests`
4. `DetectionManagerTests`

### Phase 3: Verification (Week 3)
1. `VerificationStrategyManagerTests`
2. `VerifierServiceTests`
3. `OCREngineTests`
4. `TrafficEyeVerifierTests` (with network mocks)
5. `TwoStepVerifierTests` (with network mocks)

### Phase 4: Navigation (Week 4)
1. `NavAnnouncerTests`
2. `HapticBeepControllerTests`
3. `MatchStatusSpeechTests`

### Phase 5: Integration (Week 5)
1. `FramePipelineCoordinatorIntegrationTests`
2. `AppContainerIntegrationTests`
3. `ImageUtilitiesTests`
4. `EmbeddingComputerTests`

---

## 10. CI/CD Integration

### Test Targets
- **Unit Tests**: Every push, < 2 min
- **Integration Tests**: PR merge, < 5 min
- **Snapshot Tests**: Weekly or on UI changes

### Coverage Goals
- **Core**: 90%+
- **Pipeline Services**: 85%+
- **Verification**: 80%+
- **Navigation**: 75%+
- **Utilities**: 90%+

### Xcode Test Plan
Create `thing-finderTests.xctestplan` with:
- Parallel execution enabled
- Code coverage enabled
- Test repetition for flaky test detection

---

## 11. Known Testing Challenges

| Challenge | Mitigation |
|-----------|------------|
| Vision framework requires real images | Use pre-recorded pixel buffers as fixtures |
| Network calls to TrafficEye/OpenAI | Mock URLSession with recorded responses |
| CoreML model loading | Use `ThresholdProvider` with mock model or skip in unit tests |
| ARKit requires device | Use `VideoFileFrameProvider` for simulator tests |
| Thread safety verification | Use `XCTestExpectation` with concurrent dispatch |
| Combine publisher testing | Use `XCTestExpectation` or Combine test utilities |

---

## 12. Test Naming Convention

```
test_<methodName>_<scenario>_<expectedResult>
```

Examples:
- `test_upsert_duplicateDetection_returnsNil`
- `test_tick_missCountExceedsThreshold_removesCandidate`
- `test_verify_blurryImage_rejectsWithUnclearReason`