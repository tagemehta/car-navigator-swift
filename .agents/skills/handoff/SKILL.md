---
name: handoff
description: Save or resume in-progress task state in .agents/HANDOFF.md so work can move between Devin, Claude Code, and Codex (or a fresh session) without losing context. Use when the user says handoff/switch/pause/resume, when context is getting long, or at session start if .agents/HANDOFF.md exists.
---

# Handoff

`.agents/HANDOFF.md` is the one place in-flight work lives between sessions and tools. It is gitignored and local.
Only one handoff exists at a time. Writing a new one replaces the old one.

## Resume (session start, or the user says "resume" / "continue")
1. Read `.agents/HANDOFF.md`.
2. Run `git status --short` and `git log --oneline -5`. Check that the branch and changed files match what the handoff says. If they don't, tell the user.
3. Restate the goal and the next step in one or two sentences, then continue. Do not redo work the file marks done.
4. Once the task is fully done, ask before deleting `HANDOFF.md`. Before deleting, move any durable lessons to `.agents/knowledge/learnings.md` (use the `record-learning` skill).

## Write (the user says "handoff" / "switch tools" / "pause", or your context is getting long)
Overwrite `.agents/HANDOFF.md` with exactly this structure. Keep it under ~80 lines: facts and pointers, not narration.

```markdown
# Handoff — <short task title>
Updated: <YYYY-MM-DD HH:MM> by <devin|claude-code|codex>
Branch: <branch>   Base commit: <short sha>

## Goal
<what the user asked for, in their words if possible, plus acceptance criteria>

## Decisions made (and why)
- <decision> — <reason / user said so>

## Done
- [x] <step> — <files touched>

## Next
- [ ] <the very next concrete action>
- [ ] <after that>

## Open questions for the user
- <only if blocking>

## Key locations
- `path/to/file.swift:123` — <why it matters>

## Verification status
<last build/test command and its result, or "not run">

## Gotchas discovered
- <anything surprising a fresh agent would trip over>
```

Rules:
- Point at code with `path:line`. Don't paste code blocks longer than ~5 lines.
- Record uncommitted work as file paths. Don't commit just to hand off unless the user asks.
- Never put secrets, API keys, or tokens in this file.
