# Navigation & Speech Behavior Specification

This document specifies the exact behavior of the navigation feedback system, including speech announcements, haptic beeps, and directional guidance.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    FrameNavigationManager                        │
│                    (NavigationSpeaker protocol)                  │
│                                                                  │
│  tick(at:candidates:targetBox:distance:) called every frame     │
│                                                                  │
│  ┌──────────────┐  ┌────────────────────┐  ┌─────────────────┐  │
│  │ NavAnnouncer │  │DirectionSpeechCtrl │  │HapticBeepCtrl   │  │
│  │              │  │                    │  │                 │  │
│  │ Status-based │  │ Direction words    │  │ Centering beeps │  │
│  │ phrases      │  │ with distance      │  │                 │  │
│  └──────┬───────┘  └─────────┬──────────┘  └────────┬────────┘  │
│         │                    │                      │           │
│         ▼                    ▼                      ▼           │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  AnnouncementCache                        │   │
│  │  (Shared state for phrase throttling/deduplication)       │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 1. NavAnnouncer Behavior

### Purpose
Announces match status transitions and retry reasons via speech.

### Input
- `candidates: [Candidate]` - All current candidates
- `timestamp: Date` - Current frame time

### Candidate Filtering (Priority Order)
1. **Full matches** (`.full`) - Highest priority, always announced
2. **Partial matches** (`.partial`) - Announced if no full matches
3. **All candidates** - Only if `settings.announceRejected == true` and no full/partial

### Status Transition Announcements

| From Status | To Status | Phrase Generated |
|-------------|-----------|------------------|
| Any | `.full` (with plate) | "Found matching plate {PLATE}" |
| Any | `.full` (with description) | "Found {description}" |
| Any | `.full` (no info) | "Found match" |
| Any | `.partial` (with description) | "Found {description}. Warning: Plate not visible yet" |
| Any | `.partial` (no description) | "Plate not visible yet" |
| Any | `.rejected` (with reason) | "{description} – {reason.userFriendlyDescription}" |
| Any | `.rejected` (wrong model, with direction) | "{description} – {reason} {direction}" |
| Any | `.rejected` (no info) | "Verification failed" |
| Any | `.waiting` | "Waiting for verification" |
| Any | `.lost` (angle > 60°, right) | "car was last seen {angle} degrees to the right" |
| Any | `.lost` (angle > 60°, left) | "car was last seen {angle} degrees to the left" |
| Any | `.lost` (angle ≤ 60°) | *No announcement* |
| Any | `.unknown` | *No announcement* |

### Retry Announcements (for `.unknown` status with retryable reason)

| Reject Reason | Retry Phrase |
|---------------|--------------|
| `.unclearImage` | "Picture too blurry, trying again" |
| `.insufficientInfo` | "Need a better view, retrying" |
| `.lowConfidence` | "Not sure yet, taking another shot" |
| `.apiError` | "Detection error, retrying" |
| `.licensePlateNotVisible` | "Can't see the plate, retrying" |
| `.ambiguous` | "Results unclear, retrying" |

### Cooldowns & Throttling

| Cooldown Type | Default Value | Description |
|---------------|---------------|-------------|
| `speechRepeatInterval` | 6 seconds | Same phrase won't repeat within this window |
| `waitingPhraseCooldown` | 10 seconds | "Waiting for verification" throttled globally |
| `retryPhraseCooldown` | 8 seconds | Retry phrases throttled globally |

### Suppression Rules
1. **Speech disabled**: No announcements if `settings.enableSpeech == false`
2. **Status unchanged**: No repeat for same candidate+status (except `.lost`)
3. **Global repeat**: Same phrase globally within `speechRepeatInterval` suppressed
4. **Per-candidate repeat**: Same phrase for same candidate within interval suppressed
5. **Retry already spoken**: Same retry reason for same candidate not repeated

---

## 2. DirectionSpeechController Behavior

### Purpose
Provides directional guidance ("left", "center", "right") with optional distance.

### Input
- `targetBox: CGRect?` - Bounding box of target in normalized coordinates (0-1)
- `distance: Double?` - Distance to target in meters
- `timestamp: Date` - Current frame time

### Direction Calculation
Direction is determined by `box.midX` (normalized 0-1):
- **Left**: `midX < leftThreshold` (configurable in Settings)
- **Center**: `leftThreshold ≤ midX ≤ rightThreshold`
- **Right**: `midX > rightThreshold`

### Announcement Rules

| Condition | Announcement |
|-----------|--------------|
| Direction changed, elapsed > `directionChangeInterval` | "{direction}, {distance} meters" |
| Direction unchanged, elapsed > `speechRepeatInterval` | "Still {direction}, {distance} meters" |
| No target box | *No announcement* |
| Speech disabled | *No announcement* |
| Within cooldown | *No announcement* |

### Cooldowns

| Cooldown Type | Default Value | Description |
|---------------|---------------|-------------|
| `directionChangeInterval` | 4 seconds | Minimum time between direction change announcements |
| `speechRepeatInterval` | 6 seconds | Minimum time before repeating same direction |

---

## 3. HapticBeepController Behavior

### Purpose
Provides audio feedback (beeps) that increase in frequency as target becomes more centered.

### Input
- `targetBox: CGRect?` - Bounding box of target in normalized coordinates
- `timestamp: Date` - Current frame time

### Centering Score Calculation
```
centeringScore = abs(box.midX - 0.5)  // 0 = perfectly centered, 0.5 = at edge
```

### Beep Interval Mapping
- **Centered** (score ≈ 0): Short interval (rapid beeps)
- **Off-center** (score ≈ 0.5): Long interval (slow beeps)
- Exact mapping defined by `settings.calculateBeepInterval(distanceFromCenter:)`

### State Machine

```
                    ┌─────────────────┐
                    │   Not Beeping   │
                    └────────┬────────┘
                             │
         targetBox != nil && enableBeeps
                             │
                             ▼
                    ┌─────────────────┐
                    │    Beeping      │◄──── updateInterval(smoothly: true)
                    └────────┬────────┘
                             │
         targetBox == nil || !enableBeeps
                             │
                             ▼
                    ┌─────────────────┐
                    │   Not Beeping   │
                    └─────────────────┘
```

### Rules
1. **Start beeping**: When target appears and `settings.enableBeeps == true`
2. **Update interval**: Smoothly adjust beep rate based on centering
3. **Stop beeping**: When target lost OR `settings.enableBeeps == false`

---

## 4. MatchStatusSpeech Utility

### Purpose
Pure function that generates speech phrases from match status.

### Signature
```swift
static func phrase(
    for status: MatchStatus,
    recognisedText: String?,
    detectedDescription: String?,
    rejectReason: RejectReason?,
    normalizedXPosition: CGFloat?,
    settings: Settings?,
    lastDirection: Double
) -> String?
```

### Return Values by Status

| Status | Condition | Returns |
|--------|-----------|---------|
| `.waiting` | Always | "Waiting for verification" |
| `.partial` | Has description | "Found {desc}. Warning: Plate not visible yet" |
| `.partial` | No description | "Plate not visible yet" |
| `.full` | Has plate | "Found matching plate {plate}" |
| `.full` | Has description | "Found {description}" |
| `.full` | Neither | "Found match" |
| `.rejected` | Wrong model + has position | "{desc} – {reason} {direction}" |
| `.rejected` | Has desc + reason | "{desc} – {reason.userFriendlyDescription}" |
| `.rejected` | Neither | "Verification failed" |
| `.unknown` | Always | `nil` |
| `.lost` | Angle change > 60° right | "car was last seen {angle} degrees to the right" |
| `.lost` | Angle change > 60° left | "car was last seen {angle} degrees to the left" |
| `.lost` | Angle change ≤ 60° | `nil` |

---

## 5. AnnouncementCache

### Purpose
Shared mutable state for coordinating phrase throttling across controllers.

### Properties

| Property | Type | Purpose |
|----------|------|---------|
| `lastGlobal` | `(phrase: String, time: Date)?` | Last phrase spoken globally |
| `lastByCandidate` | `[UUID: (phrase, time)]` | Last phrase per candidate |
| `lastWaitingTime` | `Date` | When "Waiting" was last spoken |
| `lastRetryTime` | `Date` | When any retry phrase was last spoken |

---

## 6. Configuration (NavigationFeedbackConfig)

| Property | Default | Description |
|----------|---------|-------------|
| `speechRepeatInterval` | 6s | Global phrase repeat suppression |
| `directionChangeInterval` | 4s | Direction change announcement cooldown |
| `waitingPhraseCooldown` | 10s | "Waiting for verification" cooldown |
| `retryPhraseCooldown` | 8s | Retry phrase cooldown |

---

## 7. Settings Dependencies

The navigation system reads these settings:

| Setting | Default | Effect |
|---------|---------|--------|
| `enableSpeech` | `true` | Master switch for all speech |
| `enableBeeps` | `true` | Master switch for haptic beeps |
| `announceRejected` | `true` | Announce rejected cars (wrong model/color) |
| `announceRetryMessages` | `true` | Announce retry messages ("Picture too blurry, trying again") |
| `announceWaitingMessages` | `true` | Announce "Waiting for verification" |
| `speechRepeatInterval` | 4s | Override for phrase repeat cooldown |
| `speechChangeInterval` | 2s | Override for direction change cooldown |
| `waitingPhraseCooldown` | 10s | Override for waiting phrase cooldown |

### Settings Separation

The settings are intentionally separated to give users fine-grained control:

- **`announceRejected`**: Controls whether *other cars* (wrong make/model/color) are announced. Users who only want to hear about their car can disable this.
- **`announceRetryMessages`**: Controls status messages like "Picture too blurry" or "Need a better view". Users who find these distracting can disable them.
- **`announceWaitingMessages`**: Controls "Waiting for verification" announcements. Users who find this redundant can disable it.

---

## 8. Testing Considerations

### Mock Requirements
- `MockSpeechOutput`: Records all `speak()` calls with timestamps
- `MockBeeper`: Records `start()` and `stop()` calls
- `MockSettings`: Configurable settings for test scenarios

### Key Test Scenarios
1. Status transitions trigger correct phrases
2. Cooldowns prevent phrase spam
3. Retry reasons generate appropriate messages
4. Direction changes are announced correctly
5. Beeps start/stop based on target presence
6. Beep interval adjusts with centering
7. Settings toggles disable features correctly
