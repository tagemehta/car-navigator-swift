# Real-image verifier eval

Evaluates the app's car-verification pipelines on **real photos** (not synthetic API output) to pick
models and prompts that balance accuracy and latency. It replaces `gpt-4.1-mini` / `gpt-4.1`, which
OpenAI removes on **2027-01-14** (suggested replacement: `gpt-6-luna`).

The older `evals/*.py` harness (see [`../README.md`](../README.md)) grades only the text-comparison step on
140 synthetic TrafficEye outputs. This one runs the full production pipelines end to end on images and grades
each step separately. It shares nothing with the synthetic harness except `evals/data/` and `evals/results/`;
prefer it for model and prompt decisions.

## What is evaluated

Four pipeline kinds, mirroring `thing-finder/Services/Pipeline/Verification/`:

| Kind | Production equivalent | Steps |
|---|---|---|
| `te:` | `TrafficEyeVerifier` (primary path) | image → TrafficEye MMR → LLM compares MMR JSON with the rider's text |
| `twostep:` | `TwoStepVerifier` (fallback after 3 TrafficEye failures) | image → LLM extracts make/model/color → same LLM comparison |
| `single:` | none yet (candidate) | image + rider's text → one LLM verdict |
| `carmen:` | none (candidate TrafficEye replacement) | image → Carmen Cloud MMR → same LLM comparison as `te:` |

Production logic is reproduced in `run_eval.py`:
- `te:` skips the LLM when `infoQ = 0.5·make + 0.3·model + 0.2·color < 0.4` (`insufficient_info`).
- `twostep:` stops when `visible_fraction < 0.5` (`occluded`) or `confidence < 0.9` (`low_confidence`).
- Only `match` counts as a match; `maybe` and every gated outcome are non-matches (a retry in the app).
- Production prompts are copied verbatim into `prompts.py` as `prod`. Variants (`v2`, `v1`) sit alongside.

Pipeline spec: `<kind>:<model>[@reasoning_effort][/prompt]`, e.g. `te:gpt-6-luna@none/v2`. The default
prompt is `prod` for `te:`, `twostep:` and `carmen:`, and `v1` for `single:`; result rows always carry the
full name (`te:gpt-6-luna@none/prod`).

### API notes that affect the Swift code
- `gpt-6-luna` supports function calling on Chat Completions **only** with `reasoning_effort: none`.
  With any other effort the harness falls back to strict `json_schema` output (or use the Responses API).
- Reasoning models take `max_completion_tokens`, not `max_tokens`; the app's `max_tokens: 50` would
  starve reasoning tokens.
- `gpt-5-mini` / `gpt-5-nano` are removed 2026-12-11, so they are not evaluated.

## Data

`build_dataset.py` writes `evals/data/realworld_cases.jsonl`: **800 images → 1,600 cases** (one positive
and one negative per image).

| Source | Images | Selection |
|---|---|---|
| VMMRdb (`datasets/VMMRdb/`) | 600 | Photos from many different users and devices, model years 2006–2016, filtered to the 72 models from `datasets/uber_eligible.json` that VMMR has; round-robin across models, ≤12 per model |
| Stanford Cars train split (`datasets/stanford_cars/` images, annotations in `datasets/archive (1)/car_devkit/devkit/*.mat`) | 200 | Cropped to the bbox + 8%; exotic makes (Bugatti, Ferrari, …) excluded |

`datasets/` is gitignored and must exist locally (see [`scripts/README.md`](../../scripts/README.md)).
`build_dataset.py` reads `datasets/uber_eligible.json` at import, so it fails without it. Cases store
absolute `image_path`s, so the JSONL files only work on the machine that built them unless rebuilt.

Both sources are forced to **≥40% side views** (`--min-side`), since the app mostly sees street-level
side views. Only ~11% of images are side-on, so the builder labels candidates in batches until the quota
is met.

VMMR folder names are mapped to `uber_eligible.json` names (`bmw_328i` → BMW 3 Series,
`mercedes benz_c300` → C-Class, `mazda_3` → Mazda3, `lexus_rx350` → RX). Missing from VMMR (data ends in
2016): Tesla Model 3/Y, Kia K5, Cadillac XT5, Lincoln Nautilus, Infiniti QX60, Mercedes GLC, Yukon XL.

DVM-CAR (`datasets/downloads/dvm-car-with-images.zip`, UK market, background removed) is downloaded but
not used yet. `load_dvm()` expects the images extracted under `datasets/dvm_car/` with `Brand$$Model$$...`
file names; that folder does not exist yet and the layout is unverified, so do not pass `--counts dvm=N`.

### Labels
- **Make/model**: from the dataset (VMMR folder / Stanford class). Treated as ground truth.
- **Color, view, body type, usable**: one `gpt-6-luna@none` vision call per image, cached in
  `evals/cache/labels/`. Known issue: the labeler marked 100% of images usable, so interiors and close-ups
  must be caught in review.

### Descriptions
`describe()` writes rider-style text from the attributes: styles `color_make_model`, `make_model`,
`color_model`, `model_only`; random aliases (Chevy, VW, Mercedes) and lowercase. Each case records which
attributes it mentions (`desc_make`, `desc_model`, `desc_color`; `null` = not mentioned).

### Negatives
Rotated per image:

| `neg_type` | Description refers to |
|---|---|
| `same_make` | another model of the same make |
| `same_body` | a different make with the same body type |
| `color_swap` | the right make/model with a clearly different color |
| `color_swap_adjacent` | the right make/model with a neighboring shade (silver↔white, black↔gray, …); report separately, it's ambiguous |
| `random` | any other car |

Half the make/model negatives keep the true color so only make/model differ.

## Grading

### End to end
Final decision vs the case label: `accuracy`, `true_match_rate` (positives matched),
`false_match_rate` (negatives matched; the error that sends a rider to the wrong car), `retry_rate`.

### Per step (`te:` and `twostep:`)
`matching.py` deterministically decides whether two names refer to the same thing:
1. normalize (lowercase, strip punctuation); make aliases (VW, Mercedes, Chevy);
2. drop a leading make from the model (`Mazda3` = `3`);
3. containment/prefix (`Escalade EXT` = `Escalade`, `3 Series` = `3`);
4. regional names TrafficEye often returns (`Cerato`=Forte, `XV`=Crosstrek, `Mondeo`=Fusion,
   `X-Trail`=Rogue, `ix35`=Tucson, `Kuga`=Escape, `QX80`=QX56, …);
5. `NEVER_MATCH` overrides containment for distinct models (Cherokee vs Grand Cherokee);
6. TrafficEye `~` groups (`Golf ~ Jetta`) match if any option matches;
7. colors by group (silver = gray, beige/gold/tan = brown; beige/gold may read as YELLOW).

Audit on the 800 TrafficEye reads: 67% exact after rules 1–3, 17% clearly wrong, 3% no vehicle, and 14%
decided by rules 4–6 (all listed and checked by hand). The lists come from this dataset's mismatches;
they're for grading here, not a general vehicle-name database.

Using those rules, `attribute()` in `run_eval.py` computes per row:

| Field | Meaning |
|---|---|
| `read_ok` | Step 1 (TrafficEye or the extractor) agrees with the truth on every attribute the description mentions. Gated outcomes (`no_vehicle`, `insufficient_info`, `occluded`, `low_confidence`) count as misreads. |
| `expected_given_read` | Correct step-2 answer given **only what step 1 output**: `match`, `mismatch`, `either` for an ambiguous `~` read that includes the described model, or `maybe` when nothing contradicts but a color the description mentions wasn't read (unread colors are unconfirmed, not agreement; `read_ok` is false for them). |
| `compare_ok` | Step 2's decision is correct for its input (`maybe` = non-match; `either` accepts match or maybe). |
| `failure` | For wrong final decisions: `misread`, `compare` (read right, comparison wrong), or `ambiguous_read`. |

Summary columns: `read_ok_rate`, `compared_rate`, `misread_error_rate`, `compare_error_rate`,
`compare_accuracy`, `compare_false_match_rate` (step 2 said match although the read contradicts the
description), `compare_missed_match_rate` (step 2 rejected although the read agrees; a retry in prod).

`single:` pipelines have no separate read, so they only get end-to-end metrics.

### Latency and cost
- `te_latency_s` is the original TrafficEye call time (cached); `llm_latency_s` sums LLM calls;
  `total_latency_s` is their sum. Measured from a laptop with 16 concurrent workers, so compare
  pipelines relative to each other rather than reading absolute numbers as phone latency.
- `usd_per_1k` is LLM cost per 1,000 verifications from token usage and `PRICES` in `common.py`
  (2026-10-16). TrafficEye costs $0.002/call extra for `te:` pipelines.
- Pipelines are interleaved in random order so latency drift affects all of them equally.

## Review site

```bash
cd evals/realworld && python3 review_app.py     # http://127.0.0.1:8765, localhost only; --port to change
```

No API calls; it reads cached TrafficEye results, every `evals/data/*.jsonl` that has a `case_id` field
(`realworld_cases`, `preview_cases`, `smoke_cases`) and every run in `evals/results/realworld/`.

- **Data tab**: one card per image with its positive (green) and negative (red) description, GPT labels,
  and TrafficEye's read. Filters: source, view, negative type, description style, review status, and
  **TrafficEye color → disagrees** (GPT color label vs TrafficEye color; 178 of 775 disagree, mostly
  neighboring shades).
- **Evals tab**: summary table (best value per column in green; click a row to focus a pipeline) and per-case
  decisions from every pipeline, with misread / compare-failure tags and what step 2 should have said.
  Filters: wrong, false match, missed match, misread, compare failure, step 2 wrong, pipelines disagree.
- **Flags** (bad color, bad view, wrong make/model, unusable, bad description) are saved to
  `evals/cache/reviews.json` by image. Flagged images are **excluded from every summary** (`flagged_images()`
  in `run_eval.py`), so reviewing after a run needs no re-run. TrafficEye correctness is computed, not reviewed.

Card fields: image = exactly what the pipelines received; bold title = ground truth (GPT color + dataset
make/model); tags = source, GPT view, GPT body type; TrafficEye line = cached MMR; ✓/✗ lines = generated
descriptions with style and negative type; grey line = image ID used by every cache file.

## Commands

### Cost guardrails
- `run_eval.py` and `build_dataset.py` print the planned request count and refuse runs over `--max-requests`
  (default 60) without `--yes`. Pass `--yes` only after the user approves the planned count; any run of
  roughly 1,000+ requests (a full 1,600-case pipeline is 1,600–3,200 requests) needs explicit approval.
- `build_dataset.py` without `--yes` uses `--max-requests` as its label-call budget and exits if the quota is
  not met; with `--yes` the budget is `--max-label-calls` (default 4000). Cached labels are free.
- TrafficEye and Carmen are called only for images missing from `evals/cache/`, and only with
  `--trafficeye-only` or `--allow-trafficeye`. Otherwise an uncached `te:`/`carmen:` case is recorded as an
  error, never billed.
- `analyze.py`, `contact_sheet.py` and `review_app.py` make no API calls.

### Setup
`pip3 install -r ../requirements.txt pillow scipy requests` (pandas, openai, Pillow, scipy, requests).
Keys: `OPENAI_API`, `TRAFFICEYE_API_KEY`, `CARMEN_API_KEY` (only for `carmen:`), read from the environment
first, then `thing-finder/Secrets.xcconfig` (`common.read_secret`), and never printed. Note the OpenAI key
name is `OPENAI_API`, not `OPENAI_API_KEY`.

### `run_eval.py` flags

| Flag | Default | Meaning |
|---|---|---|
| `--cases PATH` | required | case JSONL, e.g. `../data/realworld_cases.jsonl` |
| `--pipelines SPEC ...` | none | pipeline specs (see above) |
| `--trafficeye-only` | off | only prefetch recognition results (default pipeline `te:none`; pass `--pipelines carmen:none` for Carmen); no LLM calls |
| `--allow-trafficeye` | off | call TrafficEye/Carmen for uncached images during a normal run |
| `--limit N` | all | first N cases (files are pre-shuffled) |
| `--sources S ...` | all | filter to `stanford`, `vmmr`, `dvm` |
| `--run NAME` | timestamp | output name; re-use to resume (finished pipeline/case pairs are skipped) |
| `--workers N` | 8 | thread pool size (`full1` used 16) |
| `--max-requests N` / `--yes` | 60 / off | cost guard |

Outputs: `evals/results/realworld/<run>.jsonl` (one row per pipeline × case, appended as it goes) and
`<run>_summary.csv` (per-pipeline summary, flagged images excluded).

### Typical sequence

```bash
cd evals/realworld

# 1. Build cases (labels are cached; rebuilding with `--yes --max-label-calls 0` is free and deterministic)
python3 build_dataset.py --dry-run
python3 build_dataset.py --counts vmmr=600 stanford=200 --min-side 0.4 --yes --max-label-calls 3500

# 2. Cache TrafficEye once per image (shared by positive and negative cases)
python3 run_eval.py --cases ../data/realworld_cases.jsonl --trafficeye-only --yes

# 3. Run pipelines (resumable: re-use --run to continue)
python3 run_eval.py --cases ../data/realworld_cases.jsonl --run full1 --workers 16 --yes \
  --pipelines te:gpt-4.1-mini te:gpt-6-luna@none te:gpt-6-luna@none/v2 twostep:gpt-6-luna@none single:gpt-6-luna@none

# Small subsets
python3 run_eval.py --cases ../data/realworld_cases.jsonl --limit 20 --pipelines te:gpt-6-luna@none

# 4. Offline analysis (no API calls): CIs, McNemar tests, slices, hybrid simulation
python3 analyze.py --cases ../data/realworld_cases.jsonl --run full1   # -> results/realworld/full1_analysis.md

# Static HTML grid (default 60 cards, --n to change) of positives, or of a pipeline's errors
# -> evals/cache/contact_sheet.html (--out to change)
python3 contact_sheet.py --cases ../data/realworld_cases.jsonl --run full1 --pipeline te:gpt-6-luna@none/prod --errors-only
```

`build_dataset.py` also takes `--out` (default `evals/data/realworld_cases.jsonl`), `--seed` (42) and
`--workers` (8). `preview_cases.jsonl` (80 cases) and `smoke_cases.jsonl` (8 cases) are smaller case files
in the same schema for cheap checks.

## Files

| Path | Contents |
|---|---|
| `common.py` | paths, secrets, image loading/cropping, prices, `call_structured()` (tool vs json_schema) |
| `prompts.py` | prompt and schema variants; `prod` = verbatim from Swift |
| `trafficeye.py` | TrafficEye client with per-image cache |
| `carmen.py` | Carmen Cloud MMR client with per-image cache, mapped to TrafficEye's shape |
| `matching.py` | make/model/color equivalence rules |
| `build_dataset.py` | loaders, labeling, side-view quota, descriptions, negatives |
| `run_eval.py` | pipelines, grading, attribution, summary |
| `analyze.py` | offline report: Wilson CIs, McNemar vs baseline, slices, compare-failure kinds, hybrid replay |
| `review_app.py` / `.html` | review site |
| `contact_sheet.py` | static HTML grid |
| `evals/data/realworld_cases.jsonl` | 1,600 cases (also `preview_cases.jsonl`, `smoke_cases.jsonl`) |
| `evals/results/realworld/<run>.jsonl` / `_summary.csv` / `_analysis.md` | per-case rows / summary / `analyze.py` report. Runs on disk: `smoke1`, `smoke2`, `attr_smoke`, `carmen_smoke`, `full1`, `carmen_full` |
| `evals/cache/` (gitignored) | `labels/`, `trafficeye/`, `carmen/`, `reviews.json`, `contact_sheet.html` |

## Costs so far

| Step | Requests | Cost |
|---|---|---|
| Labeling (`gpt-6-luna@none`) | ~3,000 | ~$0.25 |
| TrafficEye | 802 | ~$1.60 |
| Smoke / attribution tests | ~150 | <$0.05 |
| `full1`: 12 pipelines × 1,600 cases | 19,200 rows, 0 errors | $4.04 |

## Results: `full1`

Full report: `evals/results/realworld/full1_analysis.md`. 1,570 cases after dropping 15 flagged
images. "Strict" false-match excludes adjacent-shade color swaps.

- **TrafficEye's read is the bottleneck.** It reads the mentioned attributes correctly in 74% of
  cases; misreads cause ~12% of all cases to be wrong for every `te:` model, against 1–3% from the
  comparison step. In the hybrid replay, ~9% of riders' own cars are hard-rejected; 64 of 68 of
  those (`te:gpt-4.1-mini`) are confident TrafficEye misreads that never escalate to TwoStep.
- **Strict false-match is ≤0.8% for every `te:`/`twostep:` pipeline** and no candidate differs
  significantly from `gpt-4.1-mini` on negatives. Adjacent shades (silver vs white) are accepted
  11–36% of the time by all of them.
- **`te:gpt-6-luna@none` beats `te:gpt-4.1-mini`** (accuracy 86.8% vs 85.0%, McNemar 41 fixed /
  13 broke, Holm p<0.001; true-match +2.8 pts; 3.4× cheaper) but its comparison call is ~0.5 s
  slower at p50 and ~1 s at p95. `gpt-5.6-luna@none` and `gpt-6-luna@low` are also significantly
  better; `@low` adds ~0.8 s more. `gpt-5.4-nano` is not significantly different from 4.1-mini.
- **Compare failures are mostly missed matches on regional names/trims** (`maybe` for
  Mondeo vs Fusion) for 4.1-mini and nano; newer models mostly fix this. The `v2` prompt removes
  color-only false matches but rejects many more regional names, so it is worse overall.
- **TwoStep is weak on side views** (52–58% true-match vs ~70% for `te:`); swapping its model
  to `gpt-6-luna@none` cuts retries (31%→21%) but not errors, and adds ~1.2 s.
- **`single:` has the best true-match (92–95%) but 5–12% strict false-match**, an order of
  magnitude worse than the two-step pipelines; unsuitable as a replacement as-is.

## Results: Carmen Cloud (`carmen_full`)

`carmen.py` calls `POST https://api.carmencloud.com/vehicle/nam` (`service=mmr`, `maxreads=1`) with
`CARMEN_API_KEY` from `Secrets.xcconfig`, caches one result per image in `evals/cache/carmen/`, and maps the
response to TrafficEye's shape (confidences ÷ 100, `colorName`, `heading` as view), so the TrafficEye
comparison prompt and the `infoQ < 0.4` gate apply unchanged. Prefetch with
`run_eval.py --cases ../data/realworld_cases.jsonl --trafficeye-only --pipelines carmen:none --yes` (needs
`CARMEN_API_KEY`).

Same 1,570 cases, comparison model `gpt-6-luna@none`, vs `te:gpt-6-luna@none/prod` from `full1`:

| | Carmen | TrafficEye |
|---|---|---|
| accuracy | 64.5% | 86.8% |
| true-match | 30.3% | 75.0% |
| strict false-match | 1.0% | 0.3% |
| retry | 60.6% | 11.3% |
| read OK | 27.9% | 74.3% |
| total p50 / p95 | 1.07 s / 2.01 s | 1.61 s / 2.49 s |

- Carmen returns no make for **52% of images** (`insufficient_info`), and for **every side view**: true-match
  0% on side, 32% front-¾, 42% rear-¾. It matches or beats TrafficEye only on straight front (82% vs 62%) and
  rear (84% vs 88%), i.e. the plate-camera angles it is built for. Resolution and region (`eur`) made no difference
  in a spot check.
- Carmen is ~0.5 s faster per recognition, but unusable as the primary recognizer for street-level views. A
  front/rear-only fallback is the only plausible role.

## Known limitations
- Color labels come from `gpt-6-luna`, which is also a candidate; the TrafficEye color cross-check and
  manual review guard against it grading itself favorably on color negatives.
- `usable` never triggers; flag interiors/close-ups in review.
- No post-2016 vehicles (VMMR cutoff); a small hand-labeled set of real app/glasses frames is the best
  remaining check of real-world accuracy.
- The matching rules were written from this dataset's mismatches; add to `REGIONAL_MODELS` /
  `NEVER_MATCH` when new data shows new cases.
