---
name: record-learning
description: Save a durable project fact (gotcha, decision, command, eval result, user preference) to the right knowledge file so future agents in any tool inherit it. Use whenever you discover something non-obvious that cost time to learn.
---

# Recording knowledge

Write a fact only if a future agent would otherwise waste time rediscovering it. Before adding anything, search the target file and update an existing entry rather than duplicating it.

## Where it goes
| Kind of knowledge | File |
|---|---|
| Rule every agent must follow every session (safety, cost, hard conventions) | `AGENTS.md`. Keep it tiny. Get the user's OK first. |
| Gotchas, decisions + rationale, eval outcomes, user preferences | `.agents/knowledge/learnings.md` |
| Architecture / folder map changes | `ONBOARDING.md` |
| Reproducible bug with no fix yet | `KNOWN_BUGS.md` |
| Verification pipeline design | `thing-finder/Services/Pipeline/Verification/README.md` |
| Navigation/audio behavior | `thing-finder/Docs/NavigationBehavior.md` |
| A repeatable multi-step procedure | A new skill at `.agents/skills/<name>/SKILL.md`, then run `python3 scripts/sync_agent_config.py` |
| In-flight task state | `.agents/HANDOFF.md` (the `handoff` skill), not here |

## Format for `learnings.md`
Add the entry under the matching heading, newest first:
```
- YYYY-MM-DD — <fact in one or two lines>. Evidence: `path:line` / command / PR. (source: <devin|claude-code|codex|user>)
```
- Use absolute dates. Never write "yesterday" or "recently".
- When a fact stops being true, delete it or mark it `[superseded YYYY-MM-DD by …]`.
- Never record secrets, keys, or personal data.
