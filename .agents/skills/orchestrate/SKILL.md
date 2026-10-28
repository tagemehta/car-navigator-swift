---
name: orchestrate
description: Plan and run multi-step work by delegating to the project's subagent roles (explorer, implementer, reviewer, test-runner) while keeping the main context small. Use for tasks spanning several files/layers, parallelizable research, or anything that would otherwise flood the main conversation.
---

# Orchestrating subagents

You are the orchestrator. You own the plan, the decisions, and the final answer. Subagents do focused work in their own context and send back a short report.
Each role has the same name in all three tools:

| Role | Access | Use it for |
|---|---|---|
| `explorer` | read-only | Find code, trace flows, answer "where/how does X work". Returns a `path:line` map. |
| `implementer` | write | Make a well-specified change in a bounded set of files, then build. |
| `reviewer` | read-only + git | Critique a diff for bugs, threading, and convention drift before you report done. |
| `test-runner` | exec | Build and run XCTest (all tests or a subset) and summarize failures. |

How to spawn one: in Devin, `run_subagent` with that profile name. In Claude Code, the Task/Agent tool with that `subagent_type`. In Codex, ask it to spawn the named custom agent.
Role definitions are generated from `.agents/roles/`. Edit those files, never the generated copies.

## When to delegate
- **Delegate:** broad or uncertain searches, reading many files, long build/test logs, independent changes that can run in parallel, and a second opinion on a diff.
- **Do it yourself:** reading one known file, small edits, and anything that needs a back-and-forth with the user. Subagents can't ask the user questions.
- Each subagent costs about as much as a fresh session. Don't fan out more than about 3 at once without a reason.

## Protocol
1. **Plan.** Write a todo list. Mark which steps are independent; those can run in parallel.
2. **Brief.** Subagents see none of your conversation, so every brief must be self-contained:
   ```
   Goal: <one sentence>
   Context: <relevant facts you already know, with path:line>
   Scope: <files/dirs it may touch; for read-only roles, what to investigate>
   Constraints: <conventions, things NOT to do, the cost gates from AGENTS.md>
   Done when: <concrete acceptance check>
   Report: <exact shape you want back, e.g. "≤15 bullets with path:line">
   ```
3. **Keep write scopes disjoint.** Two write-capable subagents must never touch the same file. Split by file or layer, or run them one after another.
4. **Integrate.** Read the reports and check claims that matter by reading the cited lines yourself. Resolve any conflicts between reports. Keep only conclusions in your context, not raw output.
5. **Verify.** After code changes: send a `test-runner` (or run the `ios-build-test` skill yourself), then a `reviewer` on the diff for non-trivial changes.
6. **Persist.** Write durable findings with the `record-learning` skill. If the work will outlive this session, write `.agents/HANDOFF.md` with the `handoff` skill.

## Context hygiene for the orchestrator
- Ask for summaries, not dumps. "Return the 5 most relevant files with one line each" beats "show me everything".
- Pipe long command output through `tail`/`rg` with `set -o pipefail`, so failures still return a nonzero exit code. Never paste full xcodebuild logs.
- Load skills only when needed. `meta-wearables-dat` in particular is large.
- If the conversation is long and the task isn't done, write a handoff and suggest the user start a fresh session.
