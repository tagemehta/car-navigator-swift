#!/usr/bin/env python3
"""Generate evaluation JSON focused on Uber-eligible makes/models.

This is a thin wrapper around the original `gen_car_eval_from_mat.py` logic.
It:
  • reads a makes/models allow-list JSON (see README below)
  • filters Stanford-Cars annotations to those makes (and optionally models)
  • writes `datasets/car_eval_uber.json`.

The allow-list format can be either:
  ["Toyota", "Honda", "Nissan", ...]                 # makes only
  or
  {"Toyota": ["Camry", "Corolla"], "Honda": ["Civic"]}  # makes + model substrings

Run:
    python scripts/gen_car_eval_uber.py --allow datasets/uber_eligible.json \
                                        --sample 400
"""
from __future__ import annotations

import argparse
import base64
import json
import random
import sys
from pathlib import Path
from typing import Dict, List

import scipy.io as sio  # pip install scipy

REPO_ROOT = Path(__file__).resolve().parent.parent
DEVKIT = REPO_ROOT / "datasets" / "archive (1)" / "car_devkit" / "devkit"
IMAGES_ROOT = REPO_ROOT / "datasets" / "stanford_cars"
OUTPUT_JSON = REPO_ROOT / "datasets" / "car_eval_uber.json"
random.seed(42)


def load_allowlist(path: Path):
    with open(path) as f:
        data = json.load(f)
    if isinstance(data, list):
        return {m.lower(): None for m in data}
    elif isinstance(data, dict):
        return {k.lower(): [s.lower() for s in v] for k, v in data.items()}
    else:
        sys.exit("Allow-list must be a JSON list or dict.")


def load_annotations() -> List[Dict]:
    meta_mat = DEVKIT / "cars_meta.mat"
    anno_mat = DEVKIT / "cars_train_annos.mat"
    if not (meta_mat.exists() and anno_mat.exists()):
        sys.exit("Annotation .mat files not found; check dataset path.")

    meta = sio.loadmat(meta_mat, squeeze_me=True)
    annos = sio.loadmat(anno_mat, squeeze_me=True)
    class_names = meta["class_names"]

    records = []
    for rec in annos["annotations"]:
        fname = rec["fname"].item() if isinstance(rec["fname"], list) else rec["fname"]
        cls_idx = int(rec["class"])
        desc = class_names[cls_idx - 1]
        records.append({"filename": fname, "description": desc})
    return records


def encode_image(path: Path) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--allow", required=True, help="Path to uber_eligible.json allow-list")
    ap.add_argument("--sample", type=int, default=400, help="Number of examples to sample")
    args = ap.parse_args()

    allow_map = load_allowlist(Path(args.allow))

    recs = load_annotations()
    filtered = []
    for r in recs:
        make, _, model = r["description"].partition(" ")
        mk_lc = make.lower()
        if mk_lc not in allow_map:
            continue
        allowed_models = allow_map[mk_lc]
        if allowed_models:
            # require any allowed substring present (case-insensitive)
            if not any(sub in r["description"].lower() for sub in allowed_models):
                continue
        filtered.append(r)

    print(f"Filtered {len(filtered)} / {len(recs)} annotations to Uber-eligible makes/models")

    sample = random.sample(filtered, min(args.sample, len(filtered)))
    cases: List[Dict] = []
    for rec in sample:
        img_path = IMAGES_ROOT / rec["filename"]
        if not img_path.exists():
            continue
        cases.append({
            "image_b64": encode_image(img_path),
            "target_description": rec["description"],
            "ground_truth_match": True,
        })

    random.shuffle(cases)
    OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_JSON, "w") as f:
        json.dump(cases, f, indent=2)
    print(f"Wrote {OUTPUT_JSON} with {len(cases)} cases (all positives)")


if __name__ == "__main__":
    main()
