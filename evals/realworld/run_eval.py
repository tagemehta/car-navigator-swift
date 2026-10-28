#!/usr/bin/env python3
"""Run verifier pipelines over real-image cases and report accuracy, latency and cost.

Pipeline specs: <kind>:<model>[@effort][/prompt]
  te:gpt-6-luna@none          cached TrafficEye MMR -> LLM text compare (production primary path)
  twostep:gpt-6-luna@none     image -> LLM extract -> LLM compare (production fallback path)
  single:gpt-6-luna@low/v1    image + description -> one LLM verdict (candidate replacement)

Examples:
  python run_eval.py --cases ../data/realworld_cases.jsonl --limit 10 \
      --pipelines te:gpt-4.1-mini te:gpt-6-luna@none single:gpt-6-luna@none
  python run_eval.py ... --yes      # required when the run exceeds --max-requests
"""

from __future__ import annotations

import argparse
import json
import random
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from pathlib import Path

import pandas as pd

import carmen
import prompts
import trafficeye
from matching import is_ambiguous, mentioned_agree
from common import (
    CACHE_DIR,
    RESULTS_DIR,
    ModelConfig,
    call_structured,
    data_url,
    load_jpeg,
)

MMR_KEYS = ("make", "model", "color", "view", "view8")


@dataclass(frozen=True)
class Pipeline:
    kind: str
    cfg: ModelConfig
    prompt: str

    @property
    def name(self) -> str:
        return f"{self.kind}:{self.cfg.name}/{self.prompt}"

    @staticmethod
    def parse(spec: str) -> "Pipeline":
        kind, _, rest = spec.partition(":")
        model_spec, _, prompt = rest.partition("/")
        default_prompt = {"te": "prod", "carmen": "prod", "twostep": "prod", "single": "v1"}
        if kind not in default_prompt:
            raise ValueError(f"unknown pipeline kind {kind!r}")
        return Pipeline(
            kind, ModelConfig.parse(model_spec), prompt or default_prompt[kind]
        )

    def planned_llm_requests(self) -> int:
        return 2 if self.kind == "twostep" else 1


def info_quality(make: float, model: float, color: float) -> float:
    return 0.5 * make + 0.3 * model + 0.2 * color


def compare(p: Pipeline, attrs: dict, description: str):
    return call_structured(
        p.cfg,
        [
            {"role": "system", "content": prompts.COMPARE_SYSTEM[p.prompt]},
            {
                "role": "user",
                "content": prompts.COMPARE_USER.format(
                    mmr_json=json.dumps(attrs, indent=2), description=description
                ),
            },
        ],
        "submit_match_decision",
        "Submit the verification probability and justification.",
        prompts.COMPARE_SCHEMA,
    )


def run_case(p: Pipeline, case: dict, prefetched: dict) -> dict:
    """Run one case. Recognition results come only from the cache or `prefetched`, keyed by
    (kind, image_id) and including failed calls, so cases never make uncounted recognition
    requests."""
    row = {
        "pipeline": p.name,
        "case_id": case["case_id"],
        "llm_latency_s": 0.0,
        "te_latency_s": 0.0,
        "cost_usd": 0.0,
        "llm_calls": 0,
        "error": None,
        "detail": None,
        # What the recognizer (TrafficEye or the TwoStep extractor) read, for error attribution.
        "seen_make": None,
        "seen_model": None,
        "seen_color": None,
    }
    jpeg = load_jpeg(Path(case["image_path"]), case.get("bbox"))

    def finish(decision: str, **extra) -> dict:
        row.update(decision=decision, **extra)
        row["total_latency_s"] = row["te_latency_s"] + row["llm_latency_s"]
        return row

    def account(res) -> None:
        row["llm_latency_s"] += res.latency_s
        row["cost_usd"] += res.cost_usd
        row["llm_calls"] += 1
        row["error"] = row["error"] or res.error

    if p.kind in RECOGNIZERS:
        rec = RECOGNIZERS[p.kind]
        te = rec.cached(case["image_id"]) or prefetched.get((p.kind, case["image_id"]))
        if te is None:
            return finish(
                "error", error=f"{p.kind} result not cached (pass --allow-trafficeye)"
            )
        row["te_latency_s"] = te["latency_s"]
        if te["error"]:
            return finish("error", error=te["error"])
        mmr = te["mmr"]
        if not mmr:
            return finish("no_vehicle")
        attrs = {
            k: {"value": mmr[k]["value"], "score": mmr[k]["score"]}
            for k in MMR_KEYS
            if mmr.get(k)
        }
        row["detail"] = " ".join(
            str(attrs.get(k, {}).get("value", "?")) for k in ("color", "make", "model")
        )
        for k in ("make", "model", "color"):
            row[f"seen_{k}"] = attrs.get(k, {}).get("value")
        score = lambda k: attrs.get(k, {}).get("score", 0)  # noqa: E731
        if info_quality(score("make"), score("model"), score("color")) < 0.4:
            return finish("insufficient_info")
        res = compare(p, attrs, case["description"])
        account(res)
        return finish(
            res.args["semantic_reason"] if res.args else "error",
            probability=(res.args or {}).get("probability_match"),
        )

    image_msg = {
        "role": "user",
        "content": [{"type": "image_url", "image_url": {"url": data_url(jpeg)}}],
    }

    if p.kind == "twostep":
        res = call_structured(
            p.cfg,
            [
                {
                    "role": "system",
                    "content": prompts.EXTRACT_SYSTEM[
                        p.prompt if p.prompt in prompts.EXTRACT_SYSTEM else "prod"
                    ],
                },
                image_msg,
            ],
            "extract_vehicle_info",
            "Extract make, model, color, body_style from the image.",
            prompts.EXTRACT_SCHEMA,
        )
        account(res)
        info = res.args
        if not info:
            return finish("error")
        row["detail"] = f"{info['color']} {info['make']} {info['model']}"
        for k in ("make", "model", "color"):
            row[f"seen_{k}"] = info[k]
        if info["visible_fraction"] < 0.5:
            return finish("occluded")
        if info["confidence"] < 0.9:
            return finish("low_confidence")
        res = compare(p, info, case["description"])
        account(res)
        return finish(
            res.args["semantic_reason"] if res.args else "error",
            probability=(res.args or {}).get("probability_match"),
        )

    # single-call vision
    res = call_structured(
        p.cfg,
        [
            {"role": "system", "content": prompts.SINGLE_SYSTEM[p.prompt]},
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": f"Rider's description: {case['description']}",
                    },
                    {"type": "image_url", "image_url": {"url": data_url(jpeg)}},
                ],
            },
        ],
        "verify_match",
        "Decide whether the photo shows the described car.",
        prompts.SINGLE_SCHEMA,
    )
    account(res)
    if not res.args:
        return finish("error")
    row["detail"] = res.args["observed"]
    verdict = {"unclear": "maybe"}.get(res.args["verdict"], res.args["verdict"])
    return finish(verdict, probability=res.args["confidence"])


# Pipelines whose step 1 is a cached recognition API; both feed the same LLM comparison.
RECOGNIZERS = {"te": trafficeye, "carmen": carmen}

GATED = {"no_vehicle", "insufficient_info", "occluded", "low_confidence"}
COMPARED = {"match", "maybe", "mismatch"}


def attribute(df: pd.DataFrame) -> pd.DataFrame:
    """Grade the read step and the comparison step of te/twostep pipelines separately.

    read_ok: the recognizer's make/model/color agree with the truth on every attribute the
      description mentions (gated decisions like no_vehicle count as misreads, and so does a
      read that omits a mentioned color: unread is not confirmed).
    expected_given_read: the correct comparison answer given only what was read:
      "match", "mismatch", "either" when an ambiguous '~' read includes the described model, or
      "maybe" when nothing contradicts but a mentioned color wasn't read (the compare prompt
      says "maybe" when info is missing).
    compare_ok: the comparison LLM's decision is correct for its input. "maybe" counts as a
      non-match, as in production; for "either", match or maybe are both acceptable; for
      "maybe", only maybe is correct.
    failure (only for wrong final decisions): "compare" if the read was right but the
      comparison was wrong, "ambiguous_read" if an ambiguous read made both answers defensible,
      otherwise "misread". "none" if correct; NaN for pipelines without a read step.
    """
    df = df.copy()
    kinds = df.pipeline.str.split(":").str[0]
    has_read = (
        kinds.isin(["te", "carmen", "twostep"])
        & df.get("desc_model", pd.Series(index=df.index)).notna()
    )
    read_ok, expected = [], []
    for r in df.itertuples():
        if not has_read[r.Index] or r.decision == "error":
            read_ok.append(None)
            expected.append(None)
            continue
        # pandas fills missing strings with NaN; the matchers expect None.
        seen = {
            k: v if isinstance(v := getattr(r, f"seen_{k}", None), str) else None
            for k in ("make", "model", "color")
        }
        if r.decision in GATED or not seen["make"]:
            read_ok.append(False)
            expected.append(None)
            continue
        described = {
            k: v if isinstance(v := getattr(r, f"desc_{k}"), str) else None
            for k in ("make", "model", "color")
        }
        truth = {
            "make": r.true_make if described["make"] else None,
            "model": r.true_model,
            "color": r.true_color if described["color"] else None,
        }
        read_ok.append(mentioned_agree(seen, truth) is True)
        agrees = mentioned_agree(seen, described)
        expected.append(
            "maybe"
            if agrees is None
            else ("either" if is_ambiguous(seen) else "match")
            if agrees
            else "mismatch"
        )
    df["read_ok"] = pd.array(read_ok, dtype="boolean")
    df["expected_given_read"] = expected
    exp, dec = df.expected_given_read, df.decision
    df["compare_ok"] = pd.array(
        [
            None
            if e is None or d not in COMPARED
            else (
                d == "match"
                if e == "match"
                else d != "match"
                if e == "mismatch"
                else d == "maybe"
                if e == "maybe"
                else d in ("match", "maybe")
            )
            for e, d in zip(exp, dec)
        ],
        dtype="boolean",
    )
    graded = has_read & df.read_ok.notna()
    wrong = graded & ~df.correct
    read_ok_b, compare_ok_b = df.read_ok.fillna(False), df.compare_ok
    df["failure"] = None
    df.loc[graded, "failure"] = "none"
    df.loc[wrong, "failure"] = "misread"
    df.loc[wrong & read_ok_b & (compare_ok_b == False), "failure"] = "compare"  # noqa: E712
    df.loc[
        wrong & read_ok_b & (compare_ok_b == True) & (exp == "either"), "failure"
    ] = "ambiguous_read"  # noqa: E712
    return df


def attribution_stats(g: pd.DataFrame) -> dict:
    nan = float("nan")
    keys = [
        "read_ok_rate",
        "compared_rate",
        "misread_error_rate",
        "compare_error_rate",
        "compare_accuracy",
        "compare_false_match_rate",
        "compare_missed_match_rate",
    ]
    if "failure" not in g or g.failure.isna().all():
        return dict.fromkeys(keys, nan)
    graded = g[g.failure.notna()]
    compared = graded[graded.compare_ok.notna()]
    should_reject = compared[compared.expected_given_read == "mismatch"]
    should_match = compared[compared.expected_given_read == "match"]
    rate = lambda mask, base: mask.sum() / len(base) if len(base) else nan  # noqa: E731
    return {
        # Step 1: share of cases where TrafficEye / the extractor read the mentioned attributes correctly.
        "read_ok_rate": graded.read_ok.astype(float).mean(),
        # Share of cases that reached the comparison step (the rest were gated out after step 1).
        "compared_rate": len(compared) / len(graded),
        # End-to-end errors split by cause, as a share of all cases.
        "misread_error_rate": (graded.failure == "misread").mean(),
        "compare_error_rate": (graded.failure == "compare").mean(),
        # Step 2 graded against its own input (what was read vs the rider's description).
        "compare_accuracy": compared.compare_ok.astype(float).mean(),
        # Step 2 said "match" although the read contradicts the description.
        "compare_false_match_rate": rate(
            should_reject.decision == "match", should_reject
        ),
        # Step 2 said maybe/mismatch although the read agrees with the description (a retry in prod).
        "compare_missed_match_rate": rate(
            should_match.decision != "match", should_match
        ),
    }


def annotate(df: pd.DataFrame, cases: pd.DataFrame) -> pd.DataFrame:
    """Join rows with case labels, grade them, and attribute errors where possible."""
    case_cols = [
        "case_id",
        "label",
        "source",
        "view",
        "neg_type",
        "true_make",
        "true_model",
        "true_color",
        "desc_make",
        "desc_model",
        "desc_color",
    ]
    df = df.merge(cases[[c for c in case_cols if c in cases]], on="case_id")
    df["pred_match"] = df["decision"] == "match"
    df["correct"] = df["pred_match"] == (df["label"] == "match")
    return attribute(df) if "desc_model" in df else df


def flagged_images() -> set[str]:
    """Images flagged in the review site; excluded from every summary."""
    path = CACHE_DIR / "reviews.json"
    reviews = json.loads(path.read_text()) if path.exists() else {}
    return {image_id for image_id, r in reviews.items() if r.get("flags")}


def summarize(df: pd.DataFrame, cases: pd.DataFrame) -> pd.DataFrame:
    if "image_id" in cases:
        cases = cases[~cases.image_id.isin(flagged_images())]
    df = annotate(df, cases)

    def agg(g: pd.DataFrame) -> pd.Series:
        pos, neg = g[g.label == "match"], g[g.label == "mismatch"]
        return pd.Series({
            "n": len(g),
            "accuracy": g.correct.mean(),
            "true_match_rate": pos.pred_match.mean() if len(pos) else float("nan"),
            "false_match_rate": neg.pred_match.mean() if len(neg) else float("nan"),
            "retry_rate": (~g.decision.isin(["match", "mismatch"])).mean(),
            "error_rate": (g.decision == "error").mean(),
            "p50_latency_s": g.total_latency_s.median(),
            "p95_latency_s": g.total_latency_s.quantile(0.95),
            "p50_llm_latency_s": g.llm_latency_s[g.llm_calls > 0].median(),
            "usd_per_1k": 1000 * g.cost_usd.mean(),
            **attribution_stats(g),
        })

    return (
        df
        .groupby("pipeline")
        .apply(agg, include_groups=False)
        .sort_values("false_match_rate")
    )


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument("--cases", type=Path, required=True)
    ap.add_argument("--pipelines", nargs="+", default=[])
    ap.add_argument(
        "--trafficeye-only",
        action="store_true",
        help="only cache TrafficEye results for the cases' images, no LLM calls",
    )
    ap.add_argument(
        "--limit", type=int, help="use the first N cases (cases are pre-shuffled)"
    )
    ap.add_argument(
        "--sources", nargs="+", help="filter to these sources (stanford, vmmr, dvm)"
    )
    ap.add_argument(
        "--run",
        default=time.strftime("%Y%m%d-%H%M%S"),
        help="run name; re-use to resume",
    )
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument(
        "--allow-trafficeye",
        action="store_true",
        help="call TrafficEye for uncached images",
    )
    ap.add_argument(
        "--max-requests", type=int, default=60, help="refuse larger runs unless --yes"
    )
    ap.add_argument("--yes", action="store_true")
    args = ap.parse_args()

    cases = pd.read_json(args.cases, lines=True)
    if args.sources:
        cases = cases[cases.source.isin(args.sources)]
    if args.limit:
        cases = cases.head(args.limit)
    if args.trafficeye_only:
        args.pipelines = args.pipelines or ["te:none"]
        args.allow_trafficeye = True
    if not args.pipelines:
        sys.exit("Pass --pipelines or --trafficeye-only")
    pipelines = [Pipeline.parse(s) for s in args.pipelines]

    out_path = RESULTS_DIR / f"{args.run}.jsonl"
    done = set()
    if out_path.exists():
        done = {
            (r["pipeline"], r["case_id"])
            for r in map(json.loads, out_path.read_text().splitlines())
        }
    todo = [
        (p, c)
        for p in pipelines
        for c in cases.to_dict("records")
        if (p.name, c["case_id"]) not in done
    ]
    # Interleave pipelines so API latency drift during the run affects all of them equally.
    random.Random(0).shuffle(todo)

    uncached = {
        (p.kind, c["image_id"])
        for p, c in todo
        if p.kind in RECOGNIZERS and not RECOGNIZERS[p.kind].cached(c["image_id"])
    }
    uncached_te = {i for _, i in uncached}
    llm_requests = (
        0 if args.trafficeye_only else sum(p.planned_llm_requests() for p, _ in todo)
    )
    te_requests = len(uncached) if args.allow_trafficeye else 0
    print(f"{len(cases)} cases x {len(pipelines)} pipelines; {len(done)} already done")
    print(
        f"Planned: up to {llm_requests} OpenAI requests, {te_requests} recognition API "
        f"requests ({len(uncached)} kind/image pairs lack cached results)"
    )
    if llm_requests + te_requests > args.max_requests and not args.yes:
        sys.exit(
            f"Exceeds --max-requests={args.max_requests}. Re-run with --yes after approval."
        )

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    prefetched: dict[tuple[str, str], dict] = {}
    if args.allow_trafficeye and uncached_te:
        # Prefetch once per image so pos/neg cases sharing an image never double-bill TrafficEye.
        jobs = {(p.kind, c["image_id"]): (p.kind, c) for p, c in todo if (p.kind, c["image_id"]) in uncached}
        with ThreadPoolExecutor(args.workers) as pool:
            results = pool.map(
                lambda kc: RECOGNIZERS[kc[0]].recognize(
                    kc[1]["image_id"], load_jpeg(Path(kc[1]["image_path"]), kc[1].get("bbox"))
                ),
                jobs.values(),
            )
            prefetched = dict(zip(jobs, results))
        failed = sum(1 for r in prefetched.values() if r["error"])
        print(f"Prefetched recognition for {len(jobs)} kind/image pairs ({failed} failed; not retried)")
    if args.trafficeye_only:
        return
    with ThreadPoolExecutor(args.workers) as pool, out_path.open("a") as out:
        futures = [pool.submit(run_case, p, c, prefetched) for p, c in todo]
        for i, fut in enumerate(as_completed(futures), 1):
            out.write(json.dumps(fut.result()) + "\n")
            out.flush()
            if i % 500 == 0 or i == len(futures):
                print(f"  {i}/{len(futures)}")

    df = pd.read_json(out_path, lines=True)
    df = df[
        df.pipeline.isin([p.name for p in pipelines]) & df.case_id.isin(cases.case_id)
    ]
    pd.set_option(
        "display.width",
        200,
        "display.max_columns",
        20,
        "display.float_format",
        "{:.3f}".format,
    )
    summary = summarize(df, cases)
    print("\n", summary)
    summary.to_csv(RESULTS_DIR / f"{args.run}_summary.csv")
    print(f"\nRows: {out_path}\nSummary: {RESULTS_DIR / f'{args.run}_summary.csv'}")


if __name__ == "__main__":
    main()
