# Learnings

Durable, non-obvious project facts shared by all agents (Devin, Claude Code, Codex).
Follow the `record-learning` skill: newest first, absolute dates, include evidence, delete or mark superseded facts.
Open bugs live in `KNOWN_BUGS.md`, not here.

## Build & tooling
- 2026-10-27 — Agent config is generated: edit `AGENTS.md`, `.agents/skills/`, `.agents/roles/`, then run `python3 scripts/sync_agent_config.py`. Claude Code only reads `.claude/skills/`, so those entries are symlinks. New custom subagent profiles only register in a fresh Devin session. (source: devin)
- 2026-10-27 — Schemes are `thing-finder` and `thing-finder-prod`. The test target is `thing-finderTests` (28 classes) with plan `thing-finderTests/thing-finder.xctestplan`. There is no CI workflow. Evidence: `xcodebuild -list`, `thing-finder/Docs/TestingPlan.md`. (source: devin)
- 2026-10-27 — The working tree may hold uncommitted Verification changes from another session. Verify behavior against `git diff`, not just HEAD. (source: devin)

## Pipeline invariants
- 2026-06-07 — Use a candidate's box for direction or depth only when `isBoundingBoxFresh` (`missCount == 0`). Drift repair deliberately sets a box to `.zero` when there's no match, to speed up eviction. Evidence: PR #24, `DriftRepairService.swift:100`. (source: git history)
- 2026-06-18 — `missThreshold` = 90 frames (was 15), with a cap of 10 candidates. The highest `missCount` is evicted first; `.partial`/`.full` are never evicted. Evidence: PRs #27, #28. (source: git history)
- 2026-10-27 — "Matched" (`isMatched`, `hasActiveMatch`) means `.full` only. `pruneToSingleMatched` removes every other candidate, not just other matches. Some `CandidateStore` reads skip the main-thread hop, and `syncOnMain` uses `main.sync`, so calling a mutator while holding a main-thread lock risks deadlock. (source: devin audit)
- 2026-09-06 — Depth APIs take a batch: `depthAt([CGPoint]) -> [Float?]`. Distance is the median of 5 points. ARKit raycasts need view coordinates (via `ImageUtilities.unscaledBoundingBoxes`), not Vision 0–1. Evidence: PR #36. (source: git history)

## Speech, haptics & navigation
- 2026-09-05 — `Speaker.speak` interrupts in-flight speech. A new speaking controller must check `AnnouncementCache` (same-tick `lastGlobal`, `priorityFrame`) and back off. `NetworkFeedbackController` runs first each tick. Evidence: `ca22ab1`, `be76566`. (source: git history)
- 2026-06-13 — Record an announcement only after speech actually fires. Recording it earlier silently drops cooldown-suppressed phrases. Evidence: `ffcb28b`. (source: git history)
- 2026-06-17 — `tick()` always runs, and each branch checks `enableSpeech` itself, so cleanup still happens with speech off (this prevents a leak). Evidence: `68ad3cb`. (source: git history)
- 2026-09-06 — The new-car earcon was removed for good (#31). Only the gated detection haptic came back (#35: 0.3 s stability, 0.5 s cooldown, suppressed after a match). Don't re-add the earcon. (source: git history)

## Verification / models / network
- 2026-10-27 — Uncommitted migration: every verifier uses `ChatCompletionRequest.verifierModel = "gpt-6-luna"` with `max_completion_tokens: 300` and `reasoning_effort: "none"` (function calling on Chat Completions requires effort `none`). TrafficEye infoQ gate 0.4 → 0.85. `maxTrafficEyeRetries` 3 → 1. In hybrid mode a TrafficEye mismatch escalates instead of rejecting. Rationale: `evals/realworld/` (rider match 75% → 90%, strict false matches 0.3% → 1.0%). (source: git diff + evals)
- 2026-10-16 — `gpt-4.1-mini` is removed from the API on 2027-01-14. (source: user)
- 2026-09-04 — TrafficEye reports network errors as an outcome (`RejectReason.networkError`), not as a publisher failure. `VerificationOutcome.didCompleteNetworkRequest` keeps local failures (blur, encoding) from clearing `APIHealthMonitor`'s degraded state. Evidence: `2482acc`, `b249bbc`. (source: git history)
- 2026-09-05 — `NetworkMonitor.currentConnectivity()` waits up to 0.3 s for the first path callback, so a Shortcut cold launch doesn't start an offline search based on a guess. (source: git history)

## Evals & Python
- 2026-10-27 — Only `evals/realworld/run_eval.py` and `build_dataset.py` refuse more than 60 requests without `--yes`. The legacy synthetic scripts have no guard (about 2,000+ requests per run). The user approves runs of about 1k+ requests. (source: devin audit, user)
- 2026-10-27 — The realworld scripts read `OPENAI_API`, `TRAFFICEYE_API_KEY`, and `CARMEN_API_KEY` from the environment first, then `Secrets.xcconfig`. Some legacy scripts use `OPENAI_API_KEY` instead. (source: devin audit)
- An IDE formatter rewrites the Python files on save. Re-read before editing. (source: user)

## Meta glasses
- 2026-04-04 — Disabled for App Store submission: the code is commented out, not deleted, and the SDK has been removed from `Package.swift`. `FeatureFlags.metaGlassesEnabled` has no effect until the code is restored. Evidence: `f60d50e`. (source: git history)

## User preferences
- 2026-10-27 — Wants to switch freely between Devin, Claude Code, and Codex in this repo. Keep shared knowledge tool-neutral, under `AGENTS.md` and `.agents/`. (source: user)
