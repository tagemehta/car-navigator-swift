# Navigation & Speech Behavior Specification

Specifies what the user hears and feels during a search: speech phrases, beeps, haptics, distance cues, connectivity warnings, and pause/resume.
Last verified against code: 2026-10-27

Source of truth: `thing-finder/Services/Pipeline/Navigation/`, `thing-finder/Utilities/Audio/`, `thing-finder/Utilities/MatchStatusSpeech.swift`, `thing-finder/Models/Settings.swift`, `thing-finder/Services/Coordinator/FramePipelineCoordinator.swift`.

---

## Architecture Overview

`FrameNavigationManager` (`NavigationManager.swift`, conforms to `NavigationSpeaker`) is built by `AppContainer.makePipeline` and called once per frame by `FramePipelineCoordinator.process` via `tick(at:candidates:targetBox:distance:)`. It runs six controllers in a fixed order:

| Order | Controller | Responsibility | Runs when |
| ----- | ---------- | -------------- | --------- |
| 1 | `NetworkFeedbackController` | Offline / restored / weak-signal warnings | Every frame |
| 2 | `PreMatchFeedbackController` | Session start, detection haptics, "Still looking" heartbeat, rejection announcements | Every frame (most parts go dormant once a `.partial`/`.full` exists) |
| 3 | `NavAnnouncer` | Match transitions (partial / full / lost), vehicle view | Every frame |
| 4 | `DirectionSpeechController` | "on your left / straight ahead / on your right" | `targetBox` is non-nil only when a `.partial`/`.full` exists |
| 5 | `DistanceMilestoneController` | "10 meters / 5 meters / 2 meters / almost there" | Only when a `.partial`/`.full` exists |
| 6 | `HapticBeepController` | Centering beeps and distance haptic pulses | Every frame |

All speaking controllers share one `AnnouncementCache` and one `HapticManager` instance. Network runs first so its cache writes are visible to later controllers in the same frame.

`reset()` resets network, pre-match, direction and milestone state (call on new search). `NavAnnouncer` and `HapticBeepController` have no `reset()`.

### Inputs from the coordinator

| Input | How it is produced (`FramePipelineCoordinator.swift`) |
| ----- | ----------------------------------------------------- |
| `at` | `Date()` wall clock at navigation time (not the capture timestamp) |
| `candidates` | Snapshot of `CandidateStore` |
| `targetBox` | Phase `.found(id)`: that candidate's box if `isBoundingBoxFresh` (`missCount == 0`). Phase `.verifying`: the first fresh `.partial` candidate's box, only if `settings.allowPartialNavigation`. Otherwise `nil`. |
| `distance` | Median of valid depths at 5 points inside `targetBox` (center and ±25% on each axis), via the batched `depthAt([CGPoint]) -> [Float?]` closure from the frame provider. `nil` if no valid sample. |

### Depth sources

| Capture source | Depth | Notes |
| -------------- | ----- | ----- |
| `.avFoundation` (`VideoCapture`, default) | `AVCaptureDepthDataOutput` depth map, `DepthFloat32`, sampled at normalized image points | Prefers `builtInLiDARDepthCamera`; falls back to triple/dual cameras, which may also deliver depth. Non-finite or <= 0 values are dropped. |
| `.arKit` (`ARVideoCapture`, `settings.useARMode`; the UI toggle is currently commented out) | `ARView` raycast (`.estimatedPlane`, `.any`) from preview-view points; distance from camera to hit | Points are converted to view coordinates (orientation + aspect-fill) before raycasting. |
| `.videoFile` (`VideoFileFrameProvider`) | Always `nil` | |
| `.metaGlasses` | Always `nil` | Provider is commented out of the build. |

Because AVFoundation dual cameras and ARKit raycasts can produce depth, distance-driven features are not strictly LiDAR-only, despite comments saying "LiDAR only".

---

## 1. AnnouncementCache

Shared reference type that coordinates throttling across controllers.

| Property | Type | Purpose |
| -------- | ---- | ------- |
| `lastGlobal` | `(phrase: String, time: Date)?` | Last phrase spoken by any controller. Every speaking controller writes it. |
| `lastByCandidate` | `[UUID: (phrase, time)]` | Last phrase per candidate (written by `NavAnnouncer`, pruned when the candidate leaves). |
| `priorityFrame` | `Date?` | Timestamp of a frame on which a connectivity warning was spoken. `isFramePreempted(_:)` returns true for that frame. |

`Speaker.speak` interrupts any in-progress utterance (`stopSpeaking(at: .word)`), so controllers that run later in the same frame defer by one frame instead of cutting off a higher-priority phrase.

---

## 2. NetworkFeedbackController

Not gated by any toggle other than the master `enableSpeech` / `enableHaptics` switches (connectivity is safety-relevant).

| Event | Phrase | Haptic (if `enableHaptics`) |
| ----- | ------ | --------------------------- |
| First tick of a session and offline | "No internet connection — search may not work" | Failure |
| Online → offline | "Connection lost — search paused" | Failure |
| Offline → online | "Connection restored — search resumed" | Success |
| Connected, `APIHealthMonitor.isDegraded` becomes true | "Weak signal — verification may be delayed" | None |
| Degraded clears | "Signal improved" | None |

Rules:
- Weak-signal transitions are ignored while offline (the outage message is clearer).
- If something was already spoken on this frame (`lastGlobal.time == timestamp`), the weak-signal transition is deferred one frame so it doesn't cut off "Connection restored".
- Every announcement sets `cache.priorityFrame`.
- `APIHealthMonitor.reset()` runs at init and on `reset()` so a previous degraded search doesn't trigger "weak signal" immediately.
- "Search paused" is literal: `VerifierService` skips network verification batches while `NetworkMonitor.isConnected == false`.

---

## 3. PreMatchFeedbackController

| Feature | Behavior | Gates |
| ------- | -------- | ----- |
| Session start | "Searching for {targetDescription}" once per search. Deferred one frame if another controller already spoke on this frame (cold offline start). Also resets the heartbeat timer. | `enableSpeech` |
| Detection haptic | Light impact (`playDetection`, intensity 0.4) once per candidate after it has had a fresh box (`missCount == 0`) continuously for >= 0.3 s; at least 0.5 s between detection haptics. If a candidate's box goes stale, its stability timer restarts. A candidate never re-fires in the same search (lifetime set). | `enableHaptics`, no `.partial`/`.full` present |
| Heartbeat | "Still looking…" every 20 s, only when there are zero candidates and nothing was spoken in the last 10 s. | `enableSpeech`, `announceWaitingMessages`, no match |
| Individual rejection | "Not yours — {detectedDescription}" or "Not yours", once per rejected candidate. Requires >= 3.5 s since `lastGlobal`. At most one rejection phrase per frame. | `enableSpeech`, `announceRejected`, no match |
| Grouped rejection | If >= 3 individual rejections occurred in the last 30 s: "Several cars nearby, still looking", at most once per 10 s. | Same as above |

A suppressed rejection is not marked as announced, so it stays eligible on later frames.

---

## 4. NavAnnouncer

### Candidate selection

1. If any `.full` candidates exist, they are active; otherwise `.partial` candidates.
2. `.lost` candidates are always appended.
3. `.waiting`, `.unknown`, `.rejected` are never announced here (rejections belong to `PreMatchFeedbackController`).

If `cache.isFramePreempted(timestamp)` (a connectivity warning spoke this frame), nothing is announced and transition state is left untouched so the announcement happens next frame.

### Phrases (`MatchStatusSpeech`)

| Transition | Phrase |
| ---------- | ------ |
| Any → `.partial` | "Possible match — plate not visible" |
| Any (except `.partial`) → `.full`, plate known (`ocrText`) | "Found it — plate {PLATE}" |
| Any (except `.partial`) → `.full`, no plate | "Found it" |
| `.partial` → `.full`, plate known | "Plate confirmed — {PLATE}" |
| `.partial` → `.full`, no plate | "Got it" |
| → `.lost`, heading delta > +60° | "car was last seen {N} degrees to the right" |
| → `.lost`, heading delta < -60° | "car was last seen {N} degrees to the left" |
| → `.lost`, abs(delta) <= 60° | None (yet) |
| `.waiting`, `.rejected`, `.unknown` | `nil` (silent) |

Compass phrasing: `delta = compareAngles(candidate.degrees, compass.degrees)` wrapped to [-180, 180]. `candidate.degrees` is the heading recorded on the last frame a detection overlapped the candidate. `CompassHeading.degrees` is stored as `360 - magneticHeading`, so the phrase describes where the car is relative to the user's current facing. `N` is rounded to the nearest 30°.

Because a `nil` phrase returns before the status is recorded, a `.lost` candidate is re-evaluated every frame until the user has turned more than 60°; the hint is then spoken once.

### Suppression rules (in order)

1. Status unchanged for this candidate: no announcement (applies to `.lost` too, to avoid bouncing between 30° buckets).
2. Haptic (if `enableHaptics`): Success on transition to `.full` or `.partial`. No haptic for rejection here. Fires even when speech is disabled.
3. `enableSpeech == false`: stop.
4. Same phrase spoken globally within `speechRepeatInterval`: suppressed.
5. Same phrase for this candidate within `speechRepeatInterval`: suppressed.

### Vehicle view

When `enableSpeech`, for each active candidate whose `view` is known and differs from the last announced view: "Front view of car", "Rear view of car", "Left side of car", "Right side of car", "Side of car". These bypass the repeat cooldowns and write `lastGlobal` with `Date()` rather than the frame timestamp.

### Retry phrases

Removed. `MatchStatusSpeech.retryPhrase(for:)` always returns `nil`; `NavigationFeedbackConfig.retryPhraseCooldown` is kept for compatibility but unused.

---

## 5. DirectionSpeechController

Change-gated direction words, spoken without distance.

- Direction from `box.midX` via `settings.getDirection`: `< directionLeftThreshold` (0.33) is "on your left"; `> directionRightThreshold` (0.66) is "on your right"; otherwise "straight ahead".
- Speaks on the first frame with a target, then only when the category changes. The same category is never repeated.
- Debounce: if any controller spoke within `directionChangeInterval` (from `settings.speechChangeInterval`, default 4 s), it waits and retries on later frames.
- Skipped when `targetBox == nil` or `enableSpeech == false`.

There is no "Still {direction}" repeat and no distance in direction phrases (removed in `acaa0fd`); beeps and milestones carry continuous guidance.

---

## 6. DistanceMilestoneController (verbal distance cues)

| Threshold | Phrase |
| --------- | ------ |
| 10 m | Locale-formatted distance, e.g. "10 meters" / "33 feet" (`MeasurementFormatter`, natural scale, long style, 0 decimals) |
| 5 m | "5 meters" (formatted) |
| 2 m | "2 meters" (formatted) |
| 1 m | "almost there" |

Rules:
- Runs only when a `.partial`/`.full` exists, `enableSpeech` is on and `distance != nil`.
- If several thresholds are crossed at once, all are marked done and only the closest is spoken.
- A threshold re-arms when distance exceeds it by more than 1.5 m (hysteresis).
- If anything was spoken in the last 1.0 s (`milestoneCooldown`), it waits; thresholds are not marked until the phrase actually plays.
- Known issue: the formatter can mix languages in non-English locales.

---

## 7. HapticBeepController

Two independent channels, both driven by `targetBox`:

| Channel | Driven by | Mapping | Gate |
| ------- | --------- | ------- | ---- |
| Beeps (`SmoothBeeper`) | Centering: `abs(box.midX - 0.5)` | `settings.calculateBeepInterval(distanceFromCenter:)`: centered gives `beepIntervalMin` (0.1 s), edge gives `beepIntervalMax` (1.0 s), shaped by `volumeCurve` | `enableBeeps` |
| Haptic pulses (`HapticManager`) | Distance | `settings.calculateBeepInterval(distanceMeters:)`: `distanceMin` (0.2 m) gives 0.1 s, `distanceMax` (20 m) gives 1.0 s, shaped by `volumeCurve`. With no distance: steady 6.0 s pulse. | `enableHaptics` |

Each channel starts when a target appears, updates its interval smoothly every frame (`updateInterval(to:smoothly: true)`), and stops when the target disappears or its toggle turns off.

Beeps are not stereo-panned. "Directional" beeping means the beep rate encodes centering; left/right comes from direction speech.

---

## 8. Audio and Haptic Primitives (`Utilities/Audio/`)

| Component | Behavior |
| --------- | -------- |
| `Speaker` | `AVSpeechSynthesizer`. Each `speak` interrupts the current utterance at a word boundary. Voice language from `settings.appLanguage` (en / es / system). Rate = `AVSpeechUtteranceMinimumSpeechRate + speechRate * (Max - Min)`; `speechRate` is 0–1 (slider in `SettingsView`, step 0.1, default 0.5). Stops immediately on `pauseAll`. |
| `SmoothBeeper` | Synthesizes a 30 ms, 1 kHz sine click with a sine envelope into `tmp/beep.wav`; plays it with `AVAudioPlayer` on a single main-runloop timer. Interval floor 0.1 s, EMA alpha 0.2 on updates; initial interval also smoothed with `settings.smoothingAlpha`. Audio session `.playback` with `.mixWithOthers` and `.duckOthers`. Stops on app background, resumes on foreground. |
| `HapticManager` | `UIImpactFeedbackGenerator(.medium)` for pulses; `playDetection` = impact at intensity 0.4; `playSuccess` / `playFailure` = `UINotificationFeedbackGenerator` success / error. Same timer and EMA model as the beeper (floor 0.1 s, alpha 0.2). |
| `AudioControl` | Posts `pauseAll` / `resumeAll` notifications. Beeper and haptics remember whether they were running and resume at the previous interval. |

Sound effects: the click is the only non-speech sound. The new-car earcon was removed in `80768cf`; it was replaced by the detection haptic (`529c42f`).

### Pause, resume and magic tap

`ContentView` attaches `.accessibilityAction(.magicTap)` (VoiceOver two-finger double tap) to the same `playbackControl()` as the Pause/Resume button: it posts `AudioControl.pauseAll()` or `resumeAll()` and toggles `isCameraRunning`. "Double Check" posts `pauseAll()`, then rebuilds the pipeline (new `detectorKey`) and restarts capture after 0.25 s + 0.25 s.

---

## 9. Configuration

### `NavigationFeedbackConfig` (`NavigationProtocol.swift`)

`FrameNavigationManager` builds it with `speechRepeatInterval = settings.speechRepeatInterval`, `directionChangeInterval = settings.speechChangeInterval`, `retryPhraseCooldown = 6` (unused).

| Property | Value | Used by |
| -------- | ----- | ------- |
| `speechRepeatInterval` | From settings (default 6 s; struct default 6 s) | `NavAnnouncer` |
| `directionChangeInterval` | From settings (default 4 s; struct default 4 s) | `DirectionSpeechController` |
| `retryPhraseCooldown` | 6 s passed (struct default 8 s) | Unused |
| `detectionHapticStabilityGate` | 0.3 s | Pre-match detection haptic |
| `detectionHapticCooldown` | 0.5 s | Pre-match detection haptic |
| `scanningHeartbeatInterval` | 20 s | Heartbeat |
| `rejectionCooldown` | 3.5 s | Individual rejections |
| `rejectionDensityWindow` | 30 s | Grouped rejections |
| `rejectionDensityLimit` | 3 | Grouped rejections |
| `milestoneCooldown` | 1.0 s | Distance milestones |

Hard-coded in controllers: heartbeat quiet window 10 s, grouped-rejection cooldown 10 s, milestone hysteresis 1.5 m, haptic steady pulse 6.0 s.

### Settings used by navigation (`Models/Settings.swift`, `@AppStorage`)

| Setting | Declared default | Effect | Exposed in UI |
| ------- | ---------------- | ------ | ------------- |
| `enableSpeech` | `true` | Master switch for all speech | Yes |
| `enableBeeps` | `true` | Centering beeps | Yes |
| `enableHaptics` | `false` | All haptics (pulses, detection, success/failure) | Yes |
| `announceRejected` | `true` | "Not yours" / grouped rejection phrases | Yes ("Announce All Detected Cars") |
| `announceWaitingMessages` | `true` | "Still looking…" heartbeat | Yes |
| `allowPartialNavigation` | `true` | Provide `targetBox` (direction, beeps, haptics) for `.partial` matches | Yes ("Navigate Before Plate Match") |
| `speechRate` | 0.5 | TTS rate fraction 0–1 | Yes |
| `speechRepeatInterval` | 6.0 s | Same-phrase suppression in `NavAnnouncer` | Advanced (1–10 s) |
| `speechChangeInterval` | 4.0 s | Direction debounce | No (slider commented out) |
| `directionLeftThreshold` / `directionRightThreshold` | 0.33 / 0.66 | Direction categories | Advanced |
| `beepIntervalMin` / `beepIntervalMax` | 0.1 s / 1.0 s | Beep and pulse interval range | Advanced |
| `distanceMin` / `distanceMax` | 0.2 m / 20.0 m | Haptic distance range | Advanced |
| `volumeCurve` | `.linear` | Shape of interval mappings | Advanced |
| `smoothingAlpha` | 0.2 | Beeper start-interval smoothing | Advanced |
| `appLanguage` | `.system` | TTS voice and localized phrases (en, es) | Yes |

Caveat: `Settings.resetToDefaults()` sets `distanceMax = 3.0` and `verificationCooldown = 2.0`, which differ from the declared defaults (20.0 and 10.0). The `speechRate` doc comment says "-1.0 to 1.0", but the code treats it as 0–1.

---

## 10. Testing

Tests live in `thing-finderTests/Navigation/` (one file per controller plus `FrameNavigationManagerTests` and `MatchStatusSpeechTests`). Mocks: `MockSpeechOutput`, `MockBeeper`, `MockHapticManager`, `MockCompassProvider`, `MockSettings`, `MockNetworkMonitor`, `MockAPIHealthMonitor`. Pass explicit timestamps to `tick` for deterministic cooldown tests. See `TestingPlan.md`.
