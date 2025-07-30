#!/usr/bin/env python3
"""Generate evaluation JSON using official Stanford Cars .mat annotations.

This script reads the annotation files that ship with the dataset:
  datasets/archive (1)/car_devkit/devkit/cars_meta.mat          — class names
  datasets/archive (1)/car_devkit/devkit/cars_train_annos.mat   — image ⇢ class mapping

It then randomly samples SAMPLE_SIZE examples, sets half of them as
negatives by shuffling descriptions, and writes
    datasets/car_eval.json
in the same schema as gen_car_eval.py.

Run with:
    python3 scripts/gen_car_eval_from_mat.py
"""
from __future__ import annotations

import base64
import json
import random
import sys
from pathlib import Path
from typing import List, Dict

import scipy.io as sio  # pip install scipy

REPO_ROOT = Path(__file__).resolve().parent.parent
DEVKIT = REPO_ROOT / "datasets" / "archive (1)" / "car_devkit" / "devkit"
IMAGES_ROOT = REPO_ROOT / "datasets" / "stanford_cars"
OUTPUT_JSON = REPO_ROOT / "datasets" / "car_eval.json"
SAMPLE_SIZE = 250
random.seed(42)


def load_annotations() -> List[Dict]:
    """Return list of {filename, description} using .mat files."""
    meta_mat = DEVKIT / "cars_meta.mat"
    anno_mat = DEVKIT / "cars_train_annos.mat"
    if not (meta_mat.exists() and anno_mat.exists()):
        sys.exit("Annotation .mat files not found; check dataset path.")

    meta = sio.loadmat(meta_mat, squeeze_me=True)
    annos = sio.loadmat(anno_mat, squeeze_me=True)
    class_names = meta["class_names"]  # array of strings

    # cars_train_annos.mat has struct array with fields: bbox_x1, y1, x2, y2, class, fname
    records = []
    for rec in annos["annotations"]:
        fname = rec["fname"].item() if isinstance(rec["fname"], list) else rec["fname"]
        cls_idx = int(rec["class"])
        desc = class_names[cls_idx - 1]  # MATLAB is 1-indexed
        records.append({"filename": fname, "description": desc})
    return records


def encode_image(path: Path) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode()


def main() -> None:
    records = load_annotations()
    if len(records) == 0:
        sys.exit("No records parsed from annotations.")

    sample = random.sample(records, min(SAMPLE_SIZE, len(records)))
    cases: List[Dict] = []
    for rec in sample:
        img_path = IMAGES_ROOT / rec["filename"]
        if not img_path.exists():
            # fallback: skip if image missing
            continue
        cases.append({
            "image_b64": encode_image(img_path),
            "target_description": rec["description"],
            "ground_truth_match": True,
        })

    # Introduce mismatches to create negatives
    shuffled_desc = [c["target_description"] for c in cases]
    random.shuffle(shuffled_desc)
    for i in range(len(cases) // 2):
        cases[i]["target_description"] = shuffled_desc[i]
        cases[i]["ground_truth_match"] = False

    random.shuffle(cases)
    OUTPUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_JSON, "w") as f:
        json.dump(cases, f, indent=2)
    print(f"Wrote {OUTPUT_JSON} with {len(cases)} cases ("+
          f"positives: {len(cases)//2}, negatives: {len(cases)//2})")


if __name__ == "__main__":
    main()
