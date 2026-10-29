# scripts/

Standalone Python/shell utilities: an API health check, dataset builders for the gitignored `datasets/`
folder, a CSV analyzer for old verifier runs, and the agent-config generator. The verifier evals live in
[`evals/`](../evals/README.md). Run everything from the repo root unless noted.

Never print or commit keys. Scripts read key **names** only from the environment, `scripts/.env`
(gitignored) or `thing-finder/Secrets.xcconfig` (gitignored).

## Scripts

| Script | Purpose | Inputs | Outputs | Env var keys | Network? | Example |
|---|---|---|---|---|---|---|
| `api_health_check.py` | Calls OpenAI and TrafficEye **through the Cloudflare proxy** (`proxy/`) the same way the app does, so it checks the proxy, its stored keys, and both APIs; meant for cron. Exit 0 only if both pass | `PROXY_BASE_URL`, `PROXY_APP_TOKEN` (env → `scripts/.env` → `Secrets.xcconfig`); embedded 100×100 test JPEG | Timestamped log lines on stdout; **every run** sends a pass/fail summary with latencies to Slack (if `SLACK_WEBHOOK_URL` is set) else a macOS notification | `PROXY_BASE_URL`, `PROXY_APP_TOKEN`, `SLACK_WEBHOOK_URL` (optional) | Yes: 1 OpenAI `gpt-6-luna` call (5 tokens) + 1 TrafficEye recognition per run (billable). Sends a `curbtocar-health-check` User-Agent because Cloudflare blocks Python's default one (error 1010) | `python3 scripts/api_health_check.py` |
| `run_api_health_check.sh` | zsh wrapper that sets `PATH`/cwd for cron, then execs `api_health_check.py` | None (paths are hard-coded to `/Users/smehta/Desktop/Dev/kraken/thing-finder`) | Whatever cron redirects; the script's failure message points to `scripts/api-health-check.log` (gitignored). No crontab entry is checked in | Same as above | Yes (via the Python script) | `scripts/run_api_health_check.sh >> scripts/api-health-check.log 2>&1` |
| `build_uber_allow.py` | Scrapes Uber's eligible-vehicles page | `--city` (default `boston`) | Overwrites `datasets/uber_eligible.json` with a **flat list of makes**. See warning below | None | Yes: `GET uber.com` (free) | `python3 scripts/build_uber_allow.py --city boston` |
| `gen_car_eval.py` | Original Stanford Cars sampler (250 cases, half negatives). **Broken**: uses `re` and `glob` without importing them, and expects class-named sub-folders that `datasets/stanford_cars/` does not have. Superseded by `gen_car_eval_from_mat.py` | `datasets/stanford_cars/**/*.jpg` | `datasets/car_eval.json` | None | No | (do not use) |
| `gen_car_eval_from_mat.py` | Samples 250 Stanford Cars train images using the official `.mat` annotations; half become negatives by shuffling descriptions | `datasets/archive (1)/car_devkit/devkit/cars_meta.mat`, `cars_train_annos.mat`; images in `datasets/stanford_cars/` | `datasets/car_eval.json`: list of `{image_b64, target_description, ground_truth_match}` (seed 42) | None | No | `python3 scripts/gen_car_eval_from_mat.py` |
| `gen_car_eval_uber.py` | Same as above, filtered to an allow-list of makes (list) or makes → model substrings (dict) | `--allow PATH` (required), `--sample N` (default 400); same `.mat` files and images | `datasets/car_eval_uber.json`, same schema, **all positives** | None | No | `python3 scripts/gen_car_eval_uber.py --allow datasets/uber_eligible.json --sample 400` |
| `vehicle_csv_analyzer.py` | Make/model/color agreement, Jaccard and confusion-matrix metrics for verifier CSVs | CSV path arg, else newest `results/twoStep_*.csv` (relative to cwd). Needs columns `ground_truth`, `predicted`, `is_match`, and `expected` for the confusion matrix | stdout only | None | No | `python3 scripts/vehicle_csv_analyzer.py results/twoStep_2025-07-23T04-07-04Z.csv` |
| `sync_agent_config.py` | Generates `.devin/agents/`, `.claude/agents/`, `.codex/agents/` and `.claude/skills/` symlinks from `.agents/roles/` and `.agents/skills/` | `.agents/` | Generated agent files; `--check` exits 1 on drift without writing | None | No | `python3 scripts/sync_agent_config.py --check` |

Dependencies: `requests` (`build_uber_allow.py`), `scipy` (`gen_car_eval*.py`). `api_health_check.py`,
`vehicle_csv_analyzer.py` and `sync_agent_config.py` use only the standard library.

### Caveats found in the code

- **`build_uber_allow.py` would break the real-image eval.** It writes a list of makes, but the checked-in
  `datasets/uber_eligible.json` is a make → models dict (e.g. `"Toyota": ["Camry", ...]`), and
  `evals/realworld/build_dataset.py` and the model filter in `gen_car_eval_uber.py` need that dict. Back up the
  file before running it; the current dict appears to be hand-curated.
- `vehicle_csv_analyzer.py`: the CSVs in `results/` have columns `image_idx,ground_truth,predicted,is_match,correct`
  with no `expected` column, so every row counts as "expected false" and accuracy/precision/recall are
  meaningless. Only the make/model/color agreement lines are valid for those files.
- `gen_car_eval_from_mat.py` labels the first half of cases negative after shuffling, so a few "negatives" may
  keep their own description.

## How `datasets/` is produced

`datasets/` and `results/` are gitignored and are not reproducible from the repo alone; downloads were manual.

| Path | Origin | Used by |
|---|---|---|
| `datasets/archive (1)/` | Stanford Cars archive (`car_devkit/devkit/*.mat`, `cars_train/`, `cars_test/`), downloaded manually | `gen_car_eval_from_mat.py`, `gen_car_eval_uber.py`, `evals/realworld/build_dataset.py` |
| `datasets/stanford_cars` | Symlink to `archive (1)/cars_train/cars_train` (flat `00001.jpg` ... files) | Same as above |
| `datasets/VMMRdb/` | VMMRdb, presumably extracted from `datasets/downloads/VMMRdb.zip`; ~715 `<make>_<model>_<year>` folders | `evals/realworld/build_dataset.py` |
| `datasets/downloads/` | Raw zips: `VMMRdb.zip`, `dvm-car-with-images.zip`, `dvm_images.zip`, `dvm_tables.zip` (~26 GB) | DVM-CAR is not used yet (`load_dvm()` expects an extracted `datasets/dvm_car/`) |
| `datasets/uber_eligible.json` | Make → model allow-list of rideshare-eligible cars | `evals/realworld/build_dataset.py` (required at import), `gen_car_eval_uber.py --allow` |
| `datasets/car_eval.json` | `gen_car_eval_from_mat.py` | Formerly `thing-finderTests/VerifierEvaluationTests.swift` (removed in commit `eddb232`), which wrote `results/twoStep_*.csv`. No current consumer |
| `datasets/car_eval_uber.json` | `gen_car_eval_uber.py` | No current consumer |

Inspect these with `ls` / `du -sh` only; the JSON files embed base64 images (35 MB and 101 MB).
