---
name: verifier-evals
description: Run or analyze the real-image car verifier evals (TrafficEye / TwoStep / LLM model and prompt comparisons) in evals/realworld. Use when comparing models, prompts, or latency for the Swift verifiers.
---

# Verifier model evals

**Prerequisite:** the eval code is tracked in git starting with the `realworld-evals` branch (commit `8c6d33d`). That branch also replaces the old `evals/**` ignore rule, which hid the whole directory. If `evals/realworld/` doesn't exist in your checkout, check `git log --oneline -1 -- evals/realworld` or `git branch -a | rg realworld-evals`. Then tell the user that branch needs to be merged or checked out. Don't recreate the scripts. Eval data (`evals/data/`) and results (`evals/results/`) are never committed: they're local only, regenerated with `build_dataset.py` / `run_eval.py`. Ask the user before regenerating, because both call paid APIs.

- Start by reading `evals/realworld/README.md`. It covers pipeline specs, dataset, and the API caveats that affect the Swift code.
- Run scripts from `evals/realworld/` with `python3`. They refuse runs over 60 API requests unless you pass `--yes`.
- **Cost gate:** ask the user before any large run. They want to approve anything around 1k requests or more. State the request count and the models first.
- Review site: `python3 evals/realworld/review_app.py`, then open http://127.0.0.1:8765.
- `datasets/` and `evals/cache/` are gitignored, so agent file tools can't read them. Inspect them with scripts instead.
- An IDE formatter rewrites the Python files on save, so re-read a file right before you edit it.
- `gpt-4.1-mini` is removed from the API on 2027-01-14. The Swift verifiers are mid-migration (uncommitted as of 2026-10-27) to `ChatCompletionRequest.verifierModel = "gpt-6-luna"` in `thing-finder/Models/OpenAIModel.swift`. Status is in `thing-finder/Services/Pipeline/Verification/README.md`.
- The older synthetic harness is `evals/run_eval.py` (see `evals/README.md`, `evals/GETTING_STARTED.md`).
- When a run finishes, record the winning config and key numbers in `.agents/knowledge/learnings.md`.
