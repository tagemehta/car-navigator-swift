#!/usr/bin/env python3
"""Generate a small evaluation set from the Stanford Cars dataset.

Produces datasets/car_eval.json containing ~250 examples with roughly
50% positive (description matches image) and 50% negative cases by
shuffling descriptions.

Prereqs: datasets/stanford_cars should contain sub-folders named like
`2012_Toyota_Prius/` filled with .jpg images (as provided by the
Stanford Cars tarballs).
"""
import base64
import json
import os
import random
import sys
from pathlib import Path
from typing import List, Dict

import scipy.io as sio

# Paths relative to repo root
REPO_ROOT = Path(__file__).resolve().parent.parent
ROOT = REPO_ROOT / "datasets" / "stanford_cars"
OUTPUT = REPO_ROOT / "datasets" / "car_eval.json"
SAMPLE_SIZE = 250  # adjust as needed

random.seed(42)

def make_description(folder_name: str) -> str:
    """Create a human-readable description from folder like '2012_Toyota_Prius'."""
    parts = re.split(r"[ _]", folder_name)
    if len(parts) < 3:
        return folder_name  # fallback
    year, make = parts[0], parts[1]
    model = " ".join(parts[2:])
    return f"{make} {model} ({year})"

def encode_image(path: str) -> str:
    with open(path, "rb") as f:
        return base64.b64encode(f.read()).decode()

def main() -> None:
    if not ROOT.exists():
        sys.exit(f"Dataset folder not found: {ROOT}\nDownload Stanford Cars first.")

    images: List[str] = glob.glob(str(ROOT / "**/*.jpg"), recursive=True)
    if len(images) == 0:
        sys.exit("No images found under stanford_cars directory.")

    sample = random.sample(images, min(SAMPLE_SIZE, len(images)))
    cases: List[Dict] = []
    for img in sample:
        folder = Path(img).parent.name
        cases.append({
            "image_b64": encode_image(img),
            "target_description": make_description(folder),
            "ground_truth_match": True,
        })

    # Make ~50% negatives by shuffling descriptions
    shuffled_desc = [c["target_description"] for c in cases]
    random.shuffle(shuffled_desc)
    for idx in range(len(cases) // 2):
        cases[idx]["target_description"] = shuffled_desc[idx]
        cases[idx]["ground_truth_match"] = False

    random.shuffle(cases)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT, "w") as f:
        json.dump(cases, f, indent=2)

    print(
        f"Wrote {OUTPUT} with {len(cases)} cases (positives: {len(cases)//2}, negatives: {len(cases)//2})"
    )

if __name__ == "__main__":
    main()
