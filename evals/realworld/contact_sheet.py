#!/usr/bin/env python3
"""Render an HTML grid of case images with their labels for human spot-checking.

  python contact_sheet.py --cases ../data/realworld_cases.jsonl --n 60
  python contact_sheet.py --cases ... --run full1 --pipeline te:gpt-6-luna@none/prod --errors-only
"""

from __future__ import annotations

import argparse
import html
import json
import random
from pathlib import Path

from common import CACHE_DIR, RESULTS_DIR, data_url, load_jpeg


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--cases", type=Path, required=True)
    ap.add_argument("--n", type=int, default=60)
    ap.add_argument("--run", help="overlay decisions from this eval run")
    ap.add_argument("--pipeline", help="pipeline name to overlay (with --run)")
    ap.add_argument("--errors-only", action="store_true", help="only cases the pipeline got wrong")
    ap.add_argument("--out", type=Path, default=CACHE_DIR / "contact_sheet.html")
    args = ap.parse_args()

    cases = [json.loads(line) for line in args.cases.read_text().splitlines()]
    results = {}
    if args.run:
        for line in (RESULTS_DIR / f"{args.run}.jsonl").read_text().splitlines():
            r = json.loads(line)
            if r["pipeline"] == args.pipeline:
                results[r["case_id"]] = r
        cases = [c for c in cases if c["case_id"] in results]
        if args.errors_only:
            cases = [c for c in cases if (results[c["case_id"]]["decision"] == "match") != (c["label"] == "match")]
    else:
        cases = [c for c in cases if c["label"] == "match"]  # one card per image for label review
    cases = random.Random(0).sample(cases, min(args.n, len(cases)))

    cards = []
    for c in cases:
        img = data_url(load_jpeg(Path(c["image_path"]), c.get("bbox")))
        lines = [
            f"<b>{html.escape(c['source'])}</b> {html.escape(c['case_id'])}",
            f"truth: {c['true_color']} {html.escape(c['true_make'])} {html.escape(c['true_model'])}",
            f"view: {c['view']} · body: {c['body_type']}",
            f"desc ({c['label']}): <i>{html.escape(c['description'])}</i>",
        ]
        if r := results.get(c["case_id"]):
            lines.append(f"→ <b>{r['decision']}</b> · saw: {html.escape(str(r.get('detail')))}")
        cards.append(f"<div class=c><img src='{img}'><div>{'<br>'.join(lines)}</div></div>")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(
        "<style>body{font:13px sans-serif;display:flex;flex-wrap:wrap;gap:10px}"
        ".c{width:300px;border:1px solid #ccc;padding:6px}img{width:100%}</style>" + "".join(cards)
    )
    print(f"Wrote {len(cards)} cards to {args.out}")


if __name__ == "__main__":
    main()
