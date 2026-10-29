# thing-finder — agent guide

This is the single source of always-on instructions for **Devin, Claude Code, and Codex**. `CLAUDE.md` only imports it.
Keep it short. Anything procedural or long belongs in a skill (`.agents/skills/`), which loads only when needed.

## Project
An assistive iOS app (Swift/SwiftUI, XCTest) that helps blind users find their rideshare car and other objects.
Per-frame pipeline: YOLO detection → Vision tracking → drift repair → candidate lifecycle → TrafficEye/LLM verification → state machine → speech/beep/haptic navigation.
User-facing name: CurbToCar. Meta Ray-Ban glasses are a live capture source on branch `meta-s26` (DAT SDK 1.0.0; on `main` the glasses code is still commented out, since 2026-04). Python eval/dataset tooling lives in `evals/` and `scripts/`.

## Meta glasses (DAT SDK) — branch `meta-s26`
- **Code:** `Services/MetaGlasses/MetaGlassesViewModel.swift` (one consolidated state machine: unconfigured → idle → registering → registered → requestingPermission → ready → streaming/paused/failed), `FramePublishers/MetaGlassesFrameProvider.swift`, `Views/MetaGlassesSettingsSection.swift`, `Views/MetaGlassesSetupView.swift`, SDK init + `onOpenURL` in `App/App.swift`. Gated by `FeatureFlags.metaGlassesEnabled`. Capture source is `.metaGlasses`.
- **Modules:** `MWDATCore` (registration, devices, permissions), `MWDATCamera` (Stream, VideoFrame), `MWDATMockDevice` (DEBUG/tests only). Package pinned `from: "1.0.0"`; the API changes between releases, so check live docs (`wearables` MCP `search_dat_docs`, or https://wearables.developer.meta.com/llms.txt?full=true) before relying on remembered signatures.
- **Flow:** `Wearables.configure()` once at launch → registration via Meta AI → camera permission → `createSession(deviceSelector:)` → wait for `.started` → `addStream(config:)` → `stream.start()`. Observe with `.listen {}` / `stateStream()`; hop to `@MainActor` for UI; never process frames on the main thread.
- **Session rules:** don't restart while `paused`; release resources only after `stopped`; opening hinges does not restart sessions.
- **Streaming config:** `.raw` codec, 720p (`.high`) / 30 fps always (no user quality setting). Lower resolution/fps would be higher quality per frame, but the Wi-Fi path handles the bandwidth.
- **Required app config** (missing items fail silently): `Info.plist` `MWDAT` dict (`AppLinkURLScheme`, `ClientToken`, `DAMEnabled`, `MetaAppID`, `TeamID`), URL scheme `thingfinder`, `NSBonjourServices`, local-network and Bluetooth usage strings, `bluetooth-central` background mode; entitlements `HotspotConfiguration` + `wifi-info`. Without the Wi-Fi/Bonjour pieces the stream stalls mid-session with no error on any channel (`8beb068`). `META_CLIENT_TOKEN` / `META_APP_ID` come from `Secrets.xcconfig` (never print them).
- **Testing:** use MockDeviceKit (no hardware needed). Real glasses need Developer Mode on in the Meta AI app (it resets after firmware updates).
- **Open bug:** phone-camera fallback / re-pair race — see `KNOWN_BUGS.md`. Deeper SDK guidance: `meta-wearables-dat` skill.

## Start of every session
1. If `.agents/HANDOFF.md` exists, follow the `handoff` skill to resume before doing anything else.
2. Read only the knowledge you need, using the map below. Don't preload big docs.

## Knowledge map (read on demand)
| Need | Read |
|---|---|
| Architecture, folder-by-folder map, data flow | `ONBOARDING.md` |
| Gotchas, past decisions, eval outcomes, preferences | `.agents/knowledge/learnings.md` |
| Open bugs, suspected bugs, inconsistencies | `KNOWN_BUGS.md` |
| Verifier design (TrafficEye / TwoStep / AdvancedLLM, OCR, models) | `thing-finder/Services/Pipeline/Verification/README.md` |
| Meta glasses SDK detail, plist/entitlements, re-enable checklist | `meta-wearables-dat` skill, `ONBOARDING.md` (Meta glasses) |
| Navigation & audio behavior | `thing-finder/Docs/NavigationBehavior.md` |
| Design decisions (current + superseded) | `thing-finder/Docs/DesignDecisions.md` |
| Test inventory, mocks, gaps | `thing-finder/Docs/TestingPlan.md` |
| Verifier evals (real-image + legacy synthetic) | `evals/README.md`, `evals/realworld/README.md` |
| Python scripts and datasets | `scripts/README.md` |

## Skills (`.agents/skills/`; invoke by name, or read the SKILL.md if your tool doesn't list it)
| Skill | Use when |
|---|---|
| `ios-build-test` | Building or running XCTest. Required before calling any Swift change done |
| `meta-wearables-dat` | Touching Meta glasses / MWDATCore / MWDATCamera code |
| `verifier-evals` | Running or analyzing verifier model/prompt evals |
| `orchestrate` | Multi-step or multi-file work; delegating to subagents |
| `handoff` | Pausing, switching tools, or resuming in-flight work |
| `record-learning` | Saving a durable fact for future agents |

## Subagent roles (same names in every tool)
`explorer` (read-only research), `implementer` (bounded edits + build), `reviewer` (diff review), `test-runner` (xcodebuild + summary).
See the `orchestrate` skill for when and how to brief them.

## Hard rules
- **Secrets:** never read aloud, log, commit, or paste the contents of `thing-finder/Secrets.xcconfig`, `scripts/.env`, or any API key.
- **API cost:** get the user's approval before any eval/script run of ~1k API requests or more. State the request count and models first.
- **Git:** don't commit, push, rewrite history, or delete branches unless the user asks for that action.
- **Gitignored data** (`datasets/`, `evals/cache/`, `CVModels/`, `results/`): agent file tools may not see it. Inspect it with scripts.
- **Editor import errors** ("No such module" in VS Code) are false positives. `xcodebuild` is the source of truth.
- **Code style:** match surrounding patterns (protocol-based services wired in `AppContainer.swift`, `@MainActor` for UI, no frame work on the main thread). Don't add or remove comments unless asked. Avoid new dependencies.
- This app guides blind users, so a wrong announcement or false "match" can physically mislead them. Favor correctness and test coverage over speed.

## Keeping knowledge and config healthy
- When you learn something non-obvious, save it with the `record-learning` skill. Hand off unfinished work with the `handoff` skill.
- Agent config sources: this file, `.agents/skills/`, `.agents/roles/`. After changing roles or adding/removing a skill, run
  `python3 scripts/sync_agent_config.py`. It regenerates `.devin/agents/`, `.claude/agents/`, `.codex/agents/`, and the `.claude/skills/` symlinks. Never edit the generated copies.
- Personal, uncommitted instructions go in `AGENTS.local.md` (gitignored).
