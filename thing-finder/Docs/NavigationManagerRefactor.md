# Navigation Manager Refactor Outline

_Last updated: 2025-07-18_

## Background & Goals

The current `NavigationManagerProtocol` implementation has grown into a **monolith** that mixes
phrase selection, speech throttling, direction feedback, and haptic/beep control.
In order to meet the project’s engineering principles—**Safe from Bugs, Easy to Understand, Ready for Change**—we will refactor it into a small set of single-purpose components driven by a frame-loop‐style API.

## High-Level Design

```
FramePipelineCoordinator.tick()
 └─> NavigationManager.tick(...)
      ├─ NavAnnouncer        (phrase decisions)
      ├─ DirectionSpeechCtl  (left / right / still announcements)
      └─ HapticBeepCtl       (beep & haptic feedback)
```

All three sub-objects are **pure decision engines** that emit value objects such as
`Announcement`, `DirectionSpeechCommand`, or `HapticCommand`. Concrete output
(e.g. `AVSpeechSynthesizer`, `CoreHaptics`) is handled by injected delegates
conforming to small protocols.

### Public API (called every frame)

```swift
protocol NavigationSpeaker {
    /// Central entry-point – call once per processed video frame.
    /// - Parameters:
    ///   - timestamp: seconds since app start (monotonic).
    ///   - candidates: snapshot from CandidateStore.
    ///   - targetBox: bounding box of the primary target, if any.
    ///   - distance: estimated distance (m) to target.
    func tick(at timestamp: TimeInterval,
              candidates: [Candidate],
              targetBox: CGRect?,
              distance: Double?)
}
```

`NavigationManager` will adopt this protocol and forward the same immutable data
snapshot to its internal controllers.

## Components

| Component                   | Responsibility                                                                                   | Key State                                                     |
| --------------------------- | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| `NavAnnouncer`              | Decide _what_ phrase (if any) should be spoken this frame based on candidate status transitions. | `AnnouncementCache` (last spoke times per candidate + global) |
| `DirectionSpeechController` | Emit direction words ("left", "right", "still") at controlled intervals.                         | last direction, last spoken time                              |
| `HapticBeepController`      | Start/stop beeps + haptic pulses keyed by candidate ID & distance.                               | currently active candidate, last beep time                    |

### AnnouncementCache structure

```swift
final class AnnouncementCache {
    var lastGlobal: (phrase:String,time:TimeInterval)?
    var lastByCandidate: [CandidateID:(phrase:String,time:TimeInterval)] = [:]
    var hasSpokenWaiting = false
}
```

The cache is injected into `NavAnnouncer` so its logic remains side-effect-free.

## Configuration

Create a dedicated struct so magic numbers live in one place:

```swift
struct NavigationFeedbackConfig {
    var speechRepeatInterval: TimeInterval = 3
    var directionChangeInterval: TimeInterval = 1
    var waitingPhraseCooldown: TimeInterval = 10
    …
}
```

`Settings` merely stores an instance of this struct. All controllers receive the
config in their initializer—no global `Settings` plumbing.

## Migration Steps

1. **Introduce protocols & config** (`SpeechOutput`, `Beeper`, `NavigationFeedbackConfig`).
2. **Extract phrase logic**<br>Move existing `announce(candidate:)` code into the pure `NavAnnouncer`.
3. **Move direction logic** into `DirectionSpeechController` (copy from existing lines 120-137).
4. **Create façade**<br>New `NavigationManager` wires sub-objects, stores caches, and implements `tick(...)`.
5. **Update callers**<br>Replace all explicit `announce(...)` invocations with a single `navigationSpeaker.tick(...)` call at the end of each pipeline frame.
6. **Delete dead code** (`announce`, redundant state vars).
7. **Add unit tests** for `NavAnnouncer` covering waiting/partial/full/rejected scenarios and throttling.

## Benefits

- **Safe from Bugs** – Stateless decision engines + single data entry-point minimise hidden coupling.
- **Easy to Understand** – Each file does one job; no scrolling through 150 lines to grasp a feature.
- **Ready for Change** – Adding a new feedback medium (e.g., Vision Pro spatial audio) means dropping in another controller without touching existing ones.

---

_Authored by Cascade AI – feel free to iterate further before implementation._
