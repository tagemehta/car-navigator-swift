#!/usr/bin/env python3
"""Local web UI to browse eval cases (pos/neg pairs) and review eval runs.

python review_app.py            # http://127.0.0.1:8765
"""

from __future__ import annotations

import argparse
import json
import math
import os
import tempfile
import threading
from functools import lru_cache
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import pandas as pd

import trafficeye
from matching import color_eq
from common import CACHE_DIR, DATA_DIR, DATASETS, RESULTS_DIR, load_jpeg
from run_eval import annotate, summarize

HERE = Path(__file__).parent
REVIEWS = CACHE_DIR / "reviews.json"
REVIEWS_LOCK = threading.Lock()


def case_files() -> list[Path]:
    """Case files in evals/data that use the realworld schema."""
    out = []
    for p in sorted(DATA_DIR.glob("*.jsonl")):
        with p.open() as f:
            first = f.readline()
        if first and "case_id" in json.loads(first):
            out.append(p)
    return out


def with_trafficeye(case: dict) -> dict:
    """Attach cached TrafficEye MMR and whether its color agrees with the GPT label."""
    te = trafficeye.cached(case["image_id"])
    mmr = (te or {}).get("mmr") or {}
    value = lambda k: (mmr.get(k) or {}).get("value")  # noqa: E731
    te_color = value("color")
    agree = color_eq(case.get("true_color"), te_color) if te_color else None
    return case | {
        "te_cached": te is not None,
        "te_desc": " ".join(filter(None, [te_color, value("make"), value("model")]))
        if mmr
        else None,
        "te_color_score": (mmr.get("color") or {}).get("score"),
        "te_view": value("view8") or value("view"),
        "te_color_agree": agree,
    }


def load_cases(name: str) -> list[dict]:
    path = next(p for p in case_files() if p.name == name)
    return [with_trafficeye(json.loads(line)) for line in path.read_text().splitlines()]


def all_cases() -> dict[str, dict]:
    return {c["case_id"]: c for p in case_files() for c in load_cases(p.name)}


def runs() -> list[str]:
    return sorted((p.stem for p in RESULTS_DIR.glob("*.jsonl")), reverse=True)


def dataset_image(image_path: str) -> Path:
    """Resolve a case's image path, refusing anything outside datasets/ (incl. via symlinks)."""
    path = Path(image_path).resolve()
    if not path.is_relative_to(DATASETS.resolve()):
        raise KeyError(f"image outside datasets/: {image_path}")
    return path


@lru_cache(maxsize=2048)
def image_bytes(case_id: str) -> bytes:
    c = all_cases()[case_id]
    return load_jpeg(dataset_image(c["image_path"]), c.get("bbox"))


def read_reviews() -> dict:
    return json.loads(REVIEWS.read_text()) if REVIEWS.exists() else {}


def update_reviews(update: dict) -> dict:
    """Apply one client's changes atomically so concurrent saves never drop each other."""
    with REVIEWS_LOCK:
        reviews = read_reviews()
        for key, value in update.items():
            if value:
                reviews[key] = value
            else:
                reviews.pop(key, None)
        REVIEWS.parent.mkdir(parents=True, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=REVIEWS.parent, prefix=".reviews-", suffix=".json")
        try:
            with os.fdopen(fd, "w") as f:
                json.dump(reviews, f, indent=1)
            os.replace(tmp, REVIEWS)
        except BaseException:
            os.unlink(tmp)
            raise
        return reviews


def clean(obj):
    """Replace NaN with None so the payload is valid JSON."""
    if isinstance(obj, float) and math.isnan(obj):
        return None
    if isinstance(obj, dict):
        return {k: clean(v) for k, v in obj.items()}
    if isinstance(obj, list):
        return [clean(v) for v in obj]
    return obj


def run_payload(name: str) -> dict:
    if name not in runs():
        raise KeyError(name)
    rows = pd.read_json(RESULTS_DIR / f"{name}.jsonl", lines=True)
    cases = all_cases()
    rows = rows[rows.case_id.isin(cases)]
    case_df = pd.DataFrame([cases[cid] for cid in rows.case_id.unique()])
    summary = summarize(rows, case_df).reset_index()
    annotated = annotate(rows, case_df)
    keep = [c for c in ("read_ok", "expected_given_read", "compare_ok", "failure") if c in annotated]
    rows = rows.merge(
        annotated[["pipeline", "case_id", *keep]],
        on=["pipeline", "case_id"],
        how="left",
    )
    rows = rows.astype(object).where(rows.notna(), None)
    return clean({
        "summary": summary.to_dict("records"),
        "rows": rows.to_dict("records"),
        "cases": case_df.to_dict("records"),
    })


class Handler(BaseHTTPRequestHandler):
    def _send(self, body: bytes, ctype: str, status: int = 200) -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj, status: int = 200) -> None:
        self._send(json.dumps(obj).encode(), "application/json", status)

    def do_GET(self) -> None:  # noqa: N802
        url = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        try:
            if url.path == "/":
                self._send(
                    (HERE / "review_app.html").read_bytes(), "text/html; charset=utf-8"
                )
            elif url.path == "/api/index":
                self._json({
                    "case_files": [p.name for p in case_files()],
                    "runs": runs(),
                })
            elif url.path == "/api/cases":
                self._json(load_cases(q["file"]))
            elif url.path == "/api/run":
                self._json(run_payload(q["name"]))
            elif url.path == "/api/reviews":
                self._json(read_reviews())
            elif url.path == "/img":
                self._send(image_bytes(q["case"]), "image/jpeg")
            else:
                self._json({"error": "not found"}, 404)
        except (KeyError, StopIteration) as e:
            self._json({"error": f"unknown: {e}"}, 404)

    def do_POST(self) -> None:  # noqa: N802
        if urlparse(self.path).path != "/api/reviews":
            return self._json({"error": "not found"}, 404)
        update = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        self._json(update_reviews(update))

    def log_message(self, *args) -> None:
        pass


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()
    print(f"Serving on http://127.0.0.1:{args.port}")
    ThreadingHTTPServer(("127.0.0.1", args.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
