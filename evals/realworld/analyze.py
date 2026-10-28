#!/usr/bin/env python3
"""Offline analysis of a finished run: confidence intervals, paired significance tests,
slices, comparison-step failure breakdown, and a production hybrid simulation.
Makes no API calls.

  python analyze.py --cases ../data/realworld_cases.jsonl --run full1
Writes results/realworld/<run>_analysis.md and prints the same report.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path

import pandas as pd
from scipy.stats import binomtest

import trafficeye
from common import RESULTS_DIR
from matching import _strip_make, color_eq, is_ambiguous, make_eq, norm
from run_eval import annotate, flagged_images, info_quality

BASELINE = {
    "te": "te:gpt-4.1-mini/prod",
    "twostep": "twostep:gpt-4.1-mini/prod",
    "single": "te:gpt-4.1-mini/prod",
}
HARD_REJECT_QUALITY = (
    0.85  # TrafficEyeVerifier: mismatch is a hard reject only at "high" quality
)
TE_RETRIES = 3  # VerifierSelector.maxTrafficEyeRetries


def wilson(k: int, n: int, z: float = 1.96) -> tuple[float, float]:
    if n == 0:
        return (math.nan, math.nan)
    p = k / n
    d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (c - h, c + h)


def rate_ci(mask: pd.Series) -> str:
    k, n = int(mask.sum()), len(mask)
    if n == 0:
        return "–"
    lo, hi = wilson(k, n)
    return f"{100 * k / n:.1f}% ({100 * lo:.1f}–{100 * hi:.1f})"


def pct(x: float) -> str:
    return "–" if pd.isna(x) else f"{100 * x:.1f}%"


def mcnemar(a: pd.Series, b: pd.Series) -> tuple[int, int, float]:
    """a, b: aligned boolean 'correct' series. Returns (b fixed, b broke, exact p)."""
    fixed, broke = int((~a & b).sum()), int((a & ~b).sum())
    n = fixed + broke
    p = binomtest(fixed, n, 0.5).pvalue if n else 1.0
    return fixed, broke, p


def holm(pvals: list[float]) -> list[float]:
    order = sorted(range(len(pvals)), key=lambda i: pvals[i])
    adj, running = [0.0] * len(pvals), 0.0
    for rank, i in enumerate(order):
        running = max(running, min(1.0, (len(pvals) - rank) * pvals[i]))
        adj[i] = running
    return adj


def md_table(df: pd.DataFrame, empty: str = "_Not applicable to this run._") -> str:
    if df.empty:
        return empty
    cols = list(df.columns)
    lines = ["| " + " | ".join(cols) + " |", "|" + "---|" * len(cols)]
    lines += ["| " + " | ".join(str(v) for v in row) + " |" for row in df.values]
    return "\n".join(lines)


def load(cases_path: Path, run: str) -> pd.DataFrame:
    cases = pd.read_json(cases_path, lines=True)
    cases = cases[~cases.image_id.isin(flagged_images())]
    rows = pd.read_json(RESULTS_DIR / f"{run}.jsonl", lines=True)
    df = annotate(rows, cases)
    extra = cases[["case_id", "image_id", "desc_style", "body_type"]]
    df = df.merge(extra, on="case_id")
    df["kind"] = df.pipeline.str.split(":").str[0]
    df["neg_strict"] = (df.label == "mismatch") & (df.neg_type != "color_swap_adjacent")
    return df


def headline(df: pd.DataFrame) -> str:
    out = []
    for name, g in df.groupby("pipeline"):
        pos, neg = g[g.label == "match"], g[g.neg_strict]
        adj = g[g.neg_type == "color_swap_adjacent"]
        out.append({
            "pipeline": name,
            "accuracy": rate_ci(g.correct),
            "true-match": rate_ci(pos.pred_match),
            "false-match (strict)": rate_ci(neg.pred_match),
            "false-match (adjacent shade)": rate_ci(adj.pred_match),
            "retry": pct((~g.decision.isin(["match", "mismatch"])).mean()),
            "_fmr": neg.pred_match.mean(),
        })
    t = pd.DataFrame(out).sort_values("_fmr").drop(columns="_fmr")
    return md_table(t)


def latency(df: pd.DataFrame) -> str:
    out = []
    for name, g in df.groupby("pipeline"):
        llm = g.llm_latency_s[g.llm_calls > 0]
        q = lambda s, x: f"{s.quantile(x):.2f}"  # noqa: E731
        out.append({
            "pipeline": name,
            "LLM p50": q(llm, 0.5),
            "LLM p90": q(llm, 0.9),
            "LLM p95": q(llm, 0.95),
            "LLM p99": q(llm, 0.99),
            "total p50": q(g.total_latency_s, 0.5),
            "total p95": q(g.total_latency_s, 0.95),
            ">3 s": pct((g.total_latency_s > 3).mean()),
            "$/1k": f"{1000 * g.cost_usd.mean():.2f}",
        })
    return md_table(pd.DataFrame(out).sort_values("LLM p50"))


def paired(df: pd.DataFrame) -> str:
    """McNemar on the same cases vs each kind's baseline, Holm-corrected per metric."""
    wide = df.pivot(index="case_id", columns="pipeline", values="correct")
    labels = df.drop_duplicates("case_id").set_index("case_id")
    subsets = {
        "all": wide.index,
        "positives": labels.index[labels.label == "match"],
        "negatives (strict)": labels.index[labels.neg_strict],
    }
    out = []
    for subset, idx in subsets.items():
        rows = []
        for p in wide.columns:
            base = BASELINE.get(p.split(":")[0])
            if base is None or base not in wide.columns or p == base:
                continue
            a, b = wide.loc[idx, base].astype(bool), wide.loc[idx, p].astype(bool)
            fixed, broke, pv = mcnemar(a, b)
            rows.append([subset, p, base, fixed, broke, pv])
        for r, adj in zip(rows, holm([r[-1] for r in rows])):
            out.append({
                "cases": r[0],
                "pipeline": r[1],
                "vs": r[2],
                "fixed": r[3],
                "broke": r[4],
                "net": r[3] - r[4],
                "p (Holm)": f"{adj:.3g}",
                "sig": "yes" if adj < 0.05 else "",
            })
    return md_table(
        pd.DataFrame(out),
        "_Skipped: no pipeline in this run has its baseline "
        f"({', '.join(sorted(set(BASELINE.values())))}) in the same run._",
    )


def head_to_head(df: pd.DataFrame, pairs: list[tuple[str, str]]) -> str:
    wide = df.pivot(index="case_id", columns="pipeline", values="correct")
    labels = df.drop_duplicates("case_id").set_index("case_id")
    out = []
    for a, b in [(a, b) for a, b in pairs if a in wide.columns and b in wide.columns]:
        for subset, idx in (
            ("all", wide.index),
            ("positives", labels.index[labels.label == "match"]),
            ("negatives (strict)", labels.index[labels.neg_strict]),
        ):
            fixed, broke, pv = mcnemar(
                wide.loc[idx, a].astype(bool), wide.loc[idx, b].astype(bool)
            )
            out.append({
                "A": a,
                "B": b,
                "cases": subset,
                "B fixed": fixed,
                "B broke": broke,
                "p (raw)": f"{pv:.3g}",
            })
    return md_table(
        pd.DataFrame(out), "_Skipped: none of the head-to-head pairs are both in this run._"
    )


def attribution(df: pd.DataFrame) -> str:
    if "failure" not in df:
        return "_Not applicable: no pipeline in this run has a read step._"
    out = []
    for name, g in df[df.failure.notna()].groupby("pipeline"):
        compared = g[g.compare_ok.notna()]
        rej = compared[compared.expected_given_read == "mismatch"]
        mat = compared[compared.expected_given_read == "match"]
        out.append({
            "pipeline": name,
            "read OK": pct(g.read_ok.astype(float).mean()),
            "reached compare": pct(len(compared) / len(g)),
            "errors: misread": pct((g.failure == "misread").mean()),
            "errors: compare": pct((g.failure == "compare").mean()),
            "errors: ambiguous": pct((g.failure == "ambiguous_read").mean()),
            "compare accuracy": rate_ci(compared.compare_ok.astype(bool)),
            "compare false-match": rate_ci(rej.decision == "match"),
            "compare missed-match": rate_ci(mat.decision != "match"),
        })
    return md_table(pd.DataFrame(out))


def slice_table(df: pd.DataFrame, col: str, pipelines: list[str], label: str) -> str:
    if not pipelines:
        return f"_Slices by {col} skipped: none of the key pipelines are in this run._"
    sub = df[df.pipeline.isin(pipelines)]
    if label == "match":
        sub, metric = sub[sub.label == "match"], "true-match"
    elif col == "neg_type":
        sub, metric = sub[sub.label == "mismatch"], "false-match"
    else:
        sub, metric = sub[sub.neg_strict], "strict false-match"
    t = sub.groupby([col, "pipeline"]).pred_match.mean().unstack("pipeline")
    n = sub[sub.pipeline == pipelines[0]].groupby(col).size().rename("n")
    t = t[pipelines].map(pct).join(n).reset_index()
    t.columns = (
        [col] + [p.replace("/prod", "").replace("/v1", "") for p in pipelines] + ["n"]
    )
    return f"**{metric} by {col}**\n\n" + md_table(t)


def compare_failure_kinds(df: pd.DataFrame) -> str:
    """Why did step 2 fail when the read was usable? Classify by what differs."""
    if "failure" not in df:
        return "_Not applicable: no pipeline in this run has a read step._"
    f = df[(df.failure == "compare")].copy()
    if f.empty:
        return "_No comparison-step failures in this run._"

    def kind(r) -> str:
        seen = {"make": r.seen_make, "model": r.seen_model, "color": r.seen_color}
        if r.decision == "match":  # false match: read contradicts description
            if r.desc_make and not make_eq(r.seen_make, r.desc_make):
                return "FM: different make"
            if (
                r.desc_color
                and color_eq(r.desc_color, r.seen_color) is False
                and (
                    norm(_strip_make(norm(r.seen_model), (r.seen_make,)))
                    == norm(_strip_make(norm(r.desc_model), (r.desc_make,)))
                    or is_ambiguous(seen)
                )
            ):
                return "FM: color only"
            return "FM: different model"
        a = _strip_make(norm(r.seen_model), (r.seen_make, r.desc_make))
        b = _strip_make(norm(r.desc_model), (r.seen_make, r.desc_make))
        if a == b:
            return "MM: same model name (" + r.decision + ")"
        if a in b or b in a or a.startswith(b) or b.startswith(a):
            return "MM: trim/containment (" + r.decision + ")"
        return "MM: regional name (" + r.decision + ")"

    f["kind"] = f.apply(kind, axis=1)
    t = f.groupby(["kind", "pipeline"]).size().unstack("pipeline").fillna(0).astype(int)
    t.columns = [c.replace("/prod", "") for c in t.columns]
    return (
        "FM = compare said match although read contradicts the description; "
        "MM = compare said maybe/mismatch although the read agrees.\n\n"
        + md_table(t.reset_index())
    )


def te_quality() -> dict[str, float]:
    out = {}
    for path in trafficeye.CACHE.glob("*.json"):
        mmr = (trafficeye.cached(path.stem) or {}).get("mmr") or {}
        s = lambda k: (mmr.get(k) or {}).get("score", 0)  # noqa: E731
        out[path.stem] = info_quality(s("make"), s("model"), s("color"))
    return out


def hybrid(df: pd.DataFrame, te_names: list[str], ts_names: list[str]) -> str:
    """Replay VerifierSelector.hybrid on the recorded results.

    TrafficEye: match -> accept; mismatch at infoQ >= 0.85 -> hard reject; anything else is
    retryable. After 3 retryable TrafficEye results the selector escalates to TwoStep, whose
    match accepts and mismatch rejects (its quality score was not recorded, so every TwoStep
    mismatch is treated as a hard reject); anything else stays unresolved.
    Assumes retries on new frames give the same TrafficEye result as this image, so the
    escalated latency (3 x TrafficEye + TwoStep) is a lower bound with no frame gaps.
    """
    q = te_quality()
    out = []
    for te in te_names:
        t = df[df.pipeline == te].set_index("case_id")
        quality = t.image_id.map(q)
        hard = (t.decision == "mismatch") & (quality >= HARD_REJECT_QUALITY)
        settled = (t.decision == "match") | hard
        for ts in ts_names:
            s = df[df.pipeline == ts].set_index("case_id").reindex(t.index)
            accept = (t.decision == "match") | (~settled & (s.decision == "match"))
            reject = hard | (~settled & (s.decision == "mismatch"))
            secs = t.total_latency_s.where(
                settled, TE_RETRIES * t.total_latency_s + s.total_latency_s
            )
            pos, neg = t.label == "match", t.neg_strict
            pos_secs = secs[pos & accept]
            out.append({
                "TE compare": te.split(":")[1].replace("/prod", ""),
                "TwoStep": ts.split(":")[1].replace("/prod", ""),
                "escalated": pct((~settled).mean()),
                "true-match": rate_ci(accept[pos]),
                "rider's car hard-rejected": pct((reject & pos).sum() / pos.sum()),
                "unresolved (pos)": pct((~accept & ~reject)[pos].mean()),
                "false-match (strict)": rate_ci(accept[neg]),
                "time-to-accept p50": f"{pos_secs.median():.2f}",
                "time-to-accept p95": f"{pos_secs.quantile(0.95):.2f}",
            })
    return md_table(pd.DataFrame(out))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cases", type=Path, required=True)
    ap.add_argument("--run", required=True)
    args = ap.parse_args()
    df = load(args.cases, args.run)
    n_cases = df.case_id.nunique()
    pipes = sorted(df.pipeline.unique())
    te = [p for p in pipes if p.startswith("te:")]
    ts = [p for p in pipes if p.startswith("twostep:")]
    key = [
        "te:gpt-4.1-mini/prod",
        "te:gpt-6-luna@none/prod",
        "te:gpt-5.4-nano@none/prod",
        "te:gpt-5.6-luna@none/prod",
        "twostep:gpt-4.1-mini/prod",
        "twostep:gpt-6-luna@none/prod",
        "single:gpt-6-luna@low/v1",
    ]
    key = [p for p in key if p in pipes]
    neg = df[df.pipeline == pipes[0]]
    sections = [
        f"# Analysis of run `{args.run}`",
        f"{n_cases} cases ({(neg.label == 'match').sum()} positive, "
        f"{neg.neg_strict.sum()} strict negatives, "
        f"{(neg.neg_type == 'color_swap_adjacent').sum()} adjacent-shade negatives) "
        f"after dropping {len(flagged_images())} flagged images. "
        "Rates show 95% Wilson intervals. 'Strict' false-match excludes adjacent-shade "
        "color swaps (e.g. silver described as white), which are reported separately.",
        "## 1. Headline (sorted by strict false-match rate)",
        headline(df),
        "## 2. Latency (seconds) and cost",
        "Measured from a laptop with 16 concurrent workers and shuffled work order, so "
        "comparable across pipelines but not absolute phone latency. `te:` totals include "
        "the cached TrafficEye latency.",
        latency(df),
        "## 3. Paired tests vs the gpt-4.1-mini baseline (exact McNemar, Holm-corrected)",
        "`fixed` = cases the candidate got right and the baseline got wrong; `broke` = the "
        "reverse. `single:` is compared with `te:gpt-4.1-mini`.",
        paired(df),
        "## 4. Head-to-head between leading candidates",
        head_to_head(
            df,
            [
                ("te:gpt-6-luna@none/prod", "te:gpt-6-luna@none/v2"),
                ("te:gpt-5.4-nano@none/prod", "te:gpt-6-luna@none/prod"),
                ("te:gpt-6-luna@none/prod", "te:gpt-5.6-luna@none/prod"),
                ("te:gpt-6-luna@none/prod", "te:gpt-6-luna@low/prod"),
            ],
        ),
        "## 5. Step attribution (read vs compare)",
        attribution(df),
        "## 6. Why the comparison step failed",
        compare_failure_kinds(df),
        "## 7. Slices",
        slice_table(df, "view", key, "match"),
        slice_table(df, "view", key, "mismatch"),
        slice_table(df, "neg_type", key, "mismatch"),
        slice_table(df, "desc_style", key, "match"),
        slice_table(df, "desc_style", key, "mismatch"),
        slice_table(df, "source", key, "match"),
        slice_table(df, "source", key, "mismatch"),
        "## 8. Production hybrid simulation (TrafficEye -> TwoStep after 3 retries)",
        (hybrid.__doc__ or "").strip().replace("\n    ", "\n"),
        hybrid(df, te, ts),
    ]
    report = "\n\n".join(sections) + "\n"
    out = RESULTS_DIR / f"{args.run}_analysis.md"
    out.write_text(report)
    print(report)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
