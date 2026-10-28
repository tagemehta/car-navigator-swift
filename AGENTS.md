# thing-finder — agent guide

This is the single source of always-on instructions for **Devin, Claude Code, and Codex**. `CLAUDE.md` only imports it.
Keep it short. Anything procedural or long belongs in a skill (`.agents/skills/`), which loads only when needed.

## Project
An assistive iOS app (Swift/SwiftUI, XCTest) that helps blind users find their rideshare car and other objects.
Per-frame pipeline: YOLO detection → Vision tracking → drift repair → candidate lifecycle → TrafficEye/LLM verification → state machine → speech/beep/haptic navigation.
User-facing name: CurbToCar. Meta Ray-Ban glasses support is implemented but commented out (disabled since 2026-04). Python eval/dataset tooling lives in `evals/` and `scripts/`.

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
