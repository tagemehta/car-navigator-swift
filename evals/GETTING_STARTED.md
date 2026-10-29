# Getting started with the synthetic LLM eval

This walks through the **synthetic** notebook (`model_comparison.ipynb`). It grades only the text-comparison
step of `TrafficEyeVerifier` on 140 made-up TrafficEye outputs. For model or prompt decisions that affect
production, use the real-image eval in [`realworld/README.md`](realworld/README.md); see
[`README.md`](README.md) for how the two relate.

## What is evaluated

The TrafficEye verifier sends an LLM:
- **Input**: TrafficEye MMR JSON (make, model, color, view, each with a confidence score)
- **Input**: the rider's description of their car
- **Output**: `semantic_reason` (match / mismatch / maybe) + `probability_match`, from which the app derives a
  reject reason

## Setup (one time)

```bash
cd evals
pip3 install -r requirements.txt
wc -l data/test_cases.jsonl            # expect 140
```

The notebook reads the `OPENAI_API` line from `thing-finder/Secrets.xcconfig` (not an environment variable).
Run Jupyter from `evals/`; the notebook uses relative paths (`data/`, `results/`, `../thing-finder/`).

## Cost guardrails

The synthetic scripts do **not** cap requests. Each notebook evaluation sends one Chat Completions request per
case: 20 for the default sample, 140 for a full run, 140 per model for the comparison loop. Run the 20-case
sample first, and get the user's approval before anything around 1,000 requests or more. See
[`README.md`](README.md#api-cost-guardrails).

## Run

```bash
jupyter notebook model_comparison.ipynb
```

Notebook sections:

| Section | What to do |
|---|---|
| 1. Setup & Data Loading | Run: imports, API key, loads `data/test_cases.jsonl` |
| 2. Production Prompt | Run. Despite the title this is a simplified prompt, not the Swift text (production copy: `trafficeye_comparison_eval.py` / `realworld/prompts.py`) |
| 3. Evaluation Functions | Run |
| 4. Run Evaluation | Runs `gpt-4.1-mini` on the first 20 cases (`limit=20`) |
| 5. Metrics & Analysis | Metrics, per-type breakdown, confusion matrix, calibration plots (one cell reads `results/gpt-5.4-nano_results.csv`) |
| 6. Failure Analysis | Worst failures by probability error |
| 7. Run Full Evaluation | Commented out; uncomment for all 140 cases, saves `results/gpt-4.1-mini_results.csv` |
| 8. Model Comparison | Commented out; loops `gpt-4.1-mini`, `gpt-4.1`, `gpt-5.4-nano`, `gpt-5.4-mini`, saves `results/{model}_results.csv` and `results/model_comparison.csv` |

Non-interactive equivalent (no confirmation prompt; 140 requests per model):

```bash
python3 run_full_analysis.py gpt-4.1-mini,gpt-5.4-nano
```

## What to look for

Last recorded results (`results/model_comparison.csv`, simplified prompt):

| Model | Decision accuracy | Reject-reason accuracy | Probability MAE |
|---|---|---|---|
| gpt-4.1-mini (production) | 93.6% | 94.3% | 0.136 |
| gpt-5.4-nano | 85.0% | 90.0% | 0.143 |

Targets: decision accuracy > 90%, reject-reason accuracy > 85%, probability MAE < 0.15.

Common failure modes: color shades ("dark blue" vs BLUE), similar models (Civic vs Accord), low MMR scores
(< 0.6).

## Iterate on prompts

1. Edit `SYSTEM_PROMPT` in section 2.
2. Re-run from section 4.
3. Compare metrics before and after.

Confirm any winner on the real-image eval before changing the app.

## Model notes

- Production: `gpt-4.1-mini`, removed by OpenAI on 2027-01-14. The real-image eval found
  `gpt-6-luna@none` a better replacement on the comparison step (see `realworld/README.md`).
- `gpt-5-mini` / `gpt-5-nano` are removed 2026-12-11.
- Prices per 1M tokens are in `realworld/common.py` (`PRICES`).

## After evaluation

To ship a change, update `TrafficEyeVerifier.swift` (model name, prompt, thresholds) and keep
`realworld/prompts.py` `prod` in sync with it.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `API key not found in Secrets.xcconfig` | Add an `OPENAI_API=...` line to `thing-finder/Secrets.xcconfig` |
| `KeyError: 'expected_reject_reason'` or `'info_score'` | You regenerated data; run `python3 add_reject_reasons.py` |
| `ModuleNotFoundError` | `pip3 install -r requirements.txt` |
| Rate limits | Increase the `time.sleep(0.1)` in `run_evaluation` (section 4) |
| Slow or costly runs | Lower `limit=` in section 4 |
