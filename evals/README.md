# Verifier evals

Python harnesses for choosing the LLM (and prompt) behind the app's car verifiers in
`thing-finder/Services/Pipeline/Verification/`. There are two, and they answer different questions:

| Harness | Location | Input | What it grades | Status |
|---|---|---|---|---|
| Synthetic (this file) | `evals/*.py`, `model_comparison.ipynb` | 140 hand-generated TrafficEye MMR JSON blobs + rider text, no images | Only the LLM comparison step of `TrafficEyeVerifier` | Older; kept for fast prompt checks |
| Real-image | [`evals/realworld/`](realworld/README.md) | 800 real car photos (VMMRdb, Stanford Cars) → 1,600 cases | Full pipelines end to end (`te:`, `twostep:`, `single:`, `carmen:`), per-step attribution, latency, cost, review site | Current; use this for model decisions |

Start with `realworld/` for anything that affects production. The synthetic set has no images, so it cannot
measure TrafficEye misreads, which the real-image eval found to be the main error source.

See [`GETTING_STARTED.md`](GETTING_STARTED.md) for a walkthrough of the synthetic notebook.

## API cost guardrails

Every eval except the offline analysis scripts calls paid APIs (OpenAI, TrafficEye, Carmen).

- `realworld/run_eval.py` and `realworld/build_dataset.py` print the planned request count and refuse to
  run more than `--max-requests` (default **60**) requests unless `--yes` is passed.
- **The synthetic scripts have no such guard.** `run_full_analysis.py` sends 140 requests per model as soon as
  it starts; `run_eval.py` uploads data and starts 8 OpenAI Evals runs (140 cases each plus a `gpt-4.1` grader
  call per case, roughly 2,000+ requests). Use `run_eval.py --dry-run` or a notebook `limit=` first.
- Get the user's approval before any run of roughly 1,000 requests or more, and before re-running TrafficEye
  or labeling calls that are already cached.

## Setup

```bash
cd evals
pip3 install -r requirements.txt        # openai, pandas, numpy, matplotlib, seaborn, jupyter
pip3 install pillow scipy requests      # also needed by realworld/ (not in requirements.txt)
```

### API keys

Never print or commit them. Each script reads them differently:

| Script | Keys read |
|---|---|
| `trafficeye_comparison_eval.py`, `run_eval.py` | `OPENAI_API_KEY` env var, else the `OPENAI_API` line in `thing-finder/Secrets.xcconfig` |
| `run_full_analysis.py`, `model_comparison.ipynb` | `OPENAI_API` in `thing-finder/Secrets.xcconfig` only |
| `analyze_results.py` | `OPENAI_API_KEY` env var (constructs `OpenAI()` at import; makes no API calls) |
| `realworld/*` | `OPENAI_API`, `TRAFFICEYE_API_KEY`, `CARMEN_API_KEY` from the environment, else `Secrets.xcconfig` |

## Synthetic harness

### Test data: `data/test_cases.jsonl`

140 cases in OpenAI Evals format (`{"item": {...}}`), each with `mmr_json`, `user_description`,
`expected_decision`, `expected_probability`, `expected_reject_reason`, `info_quality`, `info_score`,
`test_case_type`.

| `expected_decision` | Cases | `test_case_type`s |
|---|---|---|
| match | 90 | `exact_match` 15, `low_api_confidence` 15, `color_variation` 10, `abbreviation` 10, `extra_api_info` 10, `model_trim` 10, `partial_user_info` 10, `color_shade_match` 10 |
| mismatch | 40 | `wrong_make` 15, `wrong_model` 15, `wrong_color` 10 |
| maybe | 10 | `model_similarity` 10 |

`info_score = 0.5·make + 0.3·model + 0.2·color` (MMR confidences); `info_quality` is `high` (≥0.85, 118 cases),
`medium` (≥0.4, 20) or `low` (2). `expected_reject_reason` follows the `TrafficEyeVerifier` mapping:

| info_quality | match | maybe | mismatch |
|---|---|---|---|
| high | `success` | `low_confidence` | `wrong_model_or_color` |
| medium / low | `success` | `insufficient_info` | `insufficient_info` |

`data/test_cases_metadata.json` holds counts, but its `by_quality` block is stale (see Known issues).

### Regenerating the data

```bash
python3 generate_test_data.py   # overwrites data/test_cases.jsonl and test_cases_metadata.json (seed 42)
python3 add_reject_reasons.py   # REQUIRED after generating: rewrites test_cases.jsonl in place
python3 visualize_data.py       # text histograms + sample cases; no API calls
```

`generate_test_data.py` only writes `expected_reject_reason`/`info_score` for `exact_match` cases and stores
`info_quality` as a list for the rest; `add_reject_reasons.py` recomputes all three for every case. Without
it, `run_full_analysis.py` and the notebook fail with `KeyError`.

### Running

| Command | What it does | Output |
|---|---|---|
| `jupyter notebook model_comparison.ipynb` | Chat Completions + tool calling; runs 20 cases by default; full-run and multi-model cells are commented out | Inline tables/plots; full-run cells write `results/{model}_results.csv`, `results/model_comparison.csv` |
| `python3 run_full_analysis.py [model1,model2]` | Same as the notebook, all 140 cases per model (default `gpt-4.1-mini`); comma-separated models, no flags | `results/{model}_results.csv`, `results/{model}_metrics.json`, `results/model_comparison.csv` (only with 2+ models) |
| `python3 run_eval.py [--models M ...] [--dry-run]` | OpenAI **Evals API**: creates/reuses the eval "TrafficEye MMR Comparison", uploads the JSONL, one run per model (defaults to the 8 models below) | `results/eval_runs.json` |
| `python3 trafficeye_comparison_eval.py` | Creates the Evals API eval config if missing (imported by `run_eval.py`) | stdout |
| `python3 analyze_results.py [--output json\|report\|both]` | Summarizes `results/eval_runs.json` | `results/analysis.json`, `results/comparison_report.md` |

Default model list in `run_eval.py`: `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`, `gpt-5.4-nano`, `gpt-5-mini`,
`gpt-5-nano`, `gpt-4.1`, `gpt-4.1-mini`. `gpt-5-mini`/`gpt-5-nano` are removed 2026-12-11 and `gpt-4.1*` on
2027-01-14 (see `realworld/README.md`).

### Metrics (`run_full_analysis.py`, notebook)

1. Decision accuracy: `semantic_reason` equals `expected_decision`.
2. Reject-reason accuracy: reject reason computed from the model's decision + `info_quality` equals
   `expected_reject_reason`.
3. Probability MAE / RMSE vs `expected_probability`; per-decision precision; token usage; per-type breakdown.

### Results on disk

| File | Contents |
|---|---|
| `results/gpt-4.1-mini_results.csv`, `results/gpt-5.4-nano_results.csv` | Per-case rows from the notebook / `run_full_analysis.py` |
| `results/model_comparison.csv` | gpt-4.1-mini: 93.6% decision, 94.3% reject-reason accuracy; gpt-5.4-nano: 85.0% / 90.0% |
| `results/eval_runs.json` | One Evals API run (gpt-4.1-mini); see Known issues |
| `results/realworld/` | Real-image runs; see `realworld/README.md` |

### Known issues

- **Prompt drift.** The notebook (section "2. Production Prompt") and `run_full_analysis.py` use a simplified
  prompt, not the Swift production prompt. `trafficeye_comparison_eval.py` and `realworld/prompts.py`
  (`prod`) carry the production text. The CSVs above were produced with the simplified prompt.
- **Evals API path is broken.** In `eval_runs.json` the "Semantic Reason Accuracy" python grader failed all
  140 cases (likely because its code is a bare expression rather than a `grade(sample, item)` function), and `run_eval.py` saves `result_counts` as strings,
  which `analyze_results.py` cannot parse. Use the notebook, `run_full_analysis.py` or `realworld/` instead.
- `data/test_cases_metadata.json` `by_quality` reports 15/0/0 because it is computed before
  `add_reject_reasons.py` fixes `info_quality`; the JSONL itself is correct (118/20/2).

## Files

```
evals/
├── README.md, GETTING_STARTED.md
├── requirements.txt
├── model_comparison.ipynb        # interactive synthetic eval
├── generate_test_data.py         # writes data/test_cases.jsonl + metadata
├── add_reject_reasons.py         # fixes info_quality / expected_reject_reason in place
├── visualize_data.py             # text summary of test_cases.jsonl
├── run_full_analysis.py          # batch version of the notebook
├── trafficeye_comparison_eval.py # Evals API config + production prompt copy
├── run_eval.py                   # Evals API runner (legacy)
├── analyze_results.py            # Evals API result report (legacy)
├── data/
│   ├── test_cases.jsonl          # 140 synthetic cases
│   ├── test_cases_metadata.json
│   ├── realworld_cases.jsonl     # 1,600 real-image cases (realworld/)
│   ├── preview_cases.jsonl       # 80-case real-image subset
│   └── smoke_cases.jsonl         # 8-case real-image subset
├── results/                      # synthetic CSVs + results/realworld/
├── cache/                        # gitignored; realworld label / TrafficEye / Carmen caches, reviews.json
└── realworld/                    # real-image harness
```
