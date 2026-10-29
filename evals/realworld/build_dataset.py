#!/usr/bin/env python3
"""Build real-image verification cases from Stanford Cars, VMMRdb and DVM-CAR.

For each sampled image:
  1. A cheap vision model labels color / view / body type / usability (cached, one call per image).
  2. One positive case: a rider-style description of the true car ("silver chevy malibu").
  3. One hard negative: same make different model, same body type, color swap, or random.

Usage:
  python build_dataset.py --dry-run                              # default: vmmr=600 stanford=200
  python build_dataset.py --counts vmmr=600 stanford=200 --yes
"""

from __future__ import annotations

import argparse
import json
import math
import random
import re
import sys
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import scipy.io as sio

from common import (
    CACHE_DIR,
    DATA_DIR,
    DATASETS,
    ModelConfig,
    call_structured,
    data_url,
    load_jpeg,
)

LABEL_MODEL = ModelConfig("gpt-6-luna", "none")
LABEL_CACHE = CACHE_DIR / "labels"
UBER_ELIGIBLE = json.loads((DATASETS / "uber_eligible.json").read_text())

COLORS = [
    "white",
    "black",
    "silver",
    "gray",
    "red",
    "blue",
    "green",
    "brown",
    "beige",
    "gold",
    "yellow",
    "orange",
    "purple",
]
COLOR_GROUP = {
    "silver": "gray",
    "gray": "gray",
    "brown": "brown",
    "beige": "brown",
    "gold": "brown",
}
COMMON_COLORS = ["white", "black", "silver", "gray", "red", "blue"]
BODY_TYPES = [
    "sedan",
    "suv",
    "hatchback",
    "coupe",
    "convertible",
    "pickup",
    "van",
    "wagon",
    "other",
]
VIEWS = ["front", "front_three_quarter", "side", "rear_three_quarter", "rear", "other"]
ALIASES = {"Chevrolet": "Chevy", "Volkswagen": "VW", "Mercedes-Benz": "Mercedes"}
MULTIWORD_MAKES = ["AM General", "Aston Martin", "Land Rover"]
BODY_WORDS = {
    "sedan",
    "suv",
    "coupe",
    "convertible",
    "hatchback",
    "wagon",
    "van",
    "minivan",
    "cab",
    "crew",
    "extended",
    "regular",
    "club",
    "quad",
    "cargo",
    "hybrid",
    "classic",
    "sut",
}

LABEL_SCHEMA = {
    "type": "object",
    "properties": {
        "usable": {
            "type": "boolean",
            "description": "True if one car's exterior is the clear main subject",
        },
        "color": {
            "type": "string",
            "enum": COLORS + ["multicolor"],
            "description": "Main body paint color",
        },
        "view": {"type": "string", "enum": VIEWS},
        "body_type": {"type": "string", "enum": BODY_TYPES},
    },
    "required": ["usable", "color", "view", "body_type"],
    "additionalProperties": False,
}
LABEL_PROMPT = (
    "Label the main car in this photo. color = the body paint color a person would say out loud. "
    "view = camera angle relative to the car. usable = false for interiors, close-ups of parts, "
    "multiple equally prominent cars, or heavy occlusion."
)


# --- Source loaders: each returns dicts with image_id, image_path, bbox, source, make, model ---


STANFORD_EXOTIC_MAKES = {
    "Bugatti",
    "Ferrari",
    "Lamborghini",
    "McLaren",
    "Spyker",
    "Bentley",
    "Rolls-Royce",
    "Aston Martin",
    "Maybach",
    "Fisker",
    "AM General",
}
VMMR_MIN_YEAR = 2006
VMMR_MAX_PER_MODEL = 12
# VMMRdb names trims/engines instead of model lines; map them onto uber_eligible.json names.
VMMR_PATTERNS = [
    (r"bmw_(3series|3\d\d[a-z]*)", ("BMW", "3 Series")),
    (r"bmw_(5series|5\d\d[a-z]*)", ("BMW", "5 Series")),
    (r"mercedes benz_c\d+", ("Mercedes-Benz", "C-Class")),
    (r"mercedes benz_e\d+", ("Mercedes-Benz", "E-Class")),
    (r"lexus_es\d+[a-z]*", ("Lexus", "ES")),
    (r"lexus_rx\d+[a-z]*", ("Lexus", "RX")),
    (r"lexus_nx\d+[a-z]*", ("Lexus", "NX")),
    (r"mazda_3(_hatchback)?", ("Mazda", "Mazda3")),
    (r"mazda_6", ("Mazda", "Mazda6")),
    (r"gmc_yukon_1500", ("GMC", "Yukon")),
]


def load_stanford() -> list[dict]:
    devkit = DATASETS / "archive (1)" / "car_devkit" / "devkit"
    names = sio.loadmat(devkit / "cars_meta.mat", squeeze_me=True)["class_names"]
    annos = sio.loadmat(devkit / "cars_train_annos.mat", squeeze_me=True)["annotations"]
    out = []
    for a in annos:
        name = str(names[int(a["class"]) - 1])
        make = next(
            (m for m in MULTIWORD_MAKES if name.startswith(m + " ")), name.split()[0]
        )
        tokens = name[len(make) :].split()[:-1]  # drop year
        model = " ".join(t for t in tokens if t.lower() not in BODY_WORDS) or " ".join(
            tokens
        )
        if make in STANFORD_EXOTIC_MAKES:
            continue
        out.append({
            "image_id": f"stanford_{Path(str(a['fname'])).stem}",
            "image_path": str(DATASETS / "stanford_cars" / str(a["fname"])),
            "bbox": [
                int(a["bbox_x1"]),
                int(a["bbox_y1"]),
                int(a["bbox_x2"]),
                int(a["bbox_y2"]),
            ],
            "source": "stanford",
            "make": make,
            "model": model,
        })
    return out


def _norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]", "", s.lower())


def _uber_lookup() -> dict[tuple[str, str], tuple[str, str]]:
    return {
        (_norm(make), _norm(model)): (make, model)
        for make, models in UBER_ELIGIBLE.items()
        for model in models
    }


def vmmr_model(folder: str) -> tuple[str, str] | None:
    """Map a VMMRdb folder like 'honda_cr-v_2012' to ('Honda', 'CR-V'), or None if not rideshare-eligible."""
    name = folder.rsplit("_", 1)[0]
    for pattern, model in VMMR_PATTERNS:
        if re.fullmatch(pattern, name):
            return model
    parts = name.split("_")
    lookup = _uber_lookup()
    for i in range(1, len(parts)):
        key = (_norm("".join(parts[:i])), _norm("".join(parts[i:])))
        if key in lookup:
            return lookup[key]
    return None


def load_vmmr() -> list[dict]:
    """VMMRdb folders are <make>_<model>_<year>; keep rideshare-eligible models from recent years."""
    root = DATASETS / "VMMRdb"
    out = []
    for folder in sorted(p for p in root.iterdir() if p.is_dir()):
        year = folder.name.rsplit("_", 1)[-1]
        if not (year.isdigit() and int(year) >= VMMR_MIN_YEAR):
            continue
        if not (match := vmmr_model(folder.name)):
            continue
        for img in sorted(folder.glob("*.jp*g")):
            out.append({
                "image_id": f"vmmr_{_norm(folder.name)}_{_norm(img.stem)}",
                "image_path": str(img),
                "bbox": None,
                "source": "vmmr",
                "make": match[0],
                "model": match[1],
            })
    return out


def sample_balanced(
    records: list[dict], n: int, max_per_model: int | None, rng: random.Random
) -> list[dict]:
    """Sample n records round-robin across make/model so popular models don't dominate."""
    by_model: dict[tuple[str, str], list[dict]] = {}
    for r in records:
        by_model.setdefault((r["make"], r["model"]), []).append(r)
    for recs in by_model.values():
        rng.shuffle(recs)
    picked: list[dict] = []
    depth = 0
    while len(picked) < n and (max_per_model is None or depth < max_per_model):
        layer = [recs[depth] for recs in by_model.values() if depth < len(recs)]
        if not layer:
            break
        rng.shuffle(layer)
        picked += layer[: n - len(picked)]
        depth += 1
    return picked


def load_dvm() -> list[dict]:
    """DVM-CAR folders are <Brand>/<Model>/<Year>/<Colour>/*.jpg (UK market); keep side-ish views later."""
    root = DATASETS / "dvm_car"
    out = []
    for img in sorted(root.glob("**/*.jpg")):
        brand, model = img.name.split("$$")[:2]
        out.append({
            "image_id": f"dvm_{img.stem.replace('$$', '_')}",
            "image_path": str(img),
            "bbox": None,
            "source": "dvm",
            "make": brand,
            "model": model,
        })
    return out


LOADERS = {"stanford": load_stanford, "vmmr": load_vmmr, "dvm": load_dvm}


# --- Labeling ---


def label(rec: dict) -> dict | None:
    path = LABEL_CACHE / f"{rec['image_id']}.json"
    if path.exists():
        return json.loads(path.read_text())
    jpeg = load_jpeg(Path(rec["image_path"]), rec["bbox"])
    res = call_structured(
        LABEL_MODEL,
        [
            {"role": "system", "content": LABEL_PROMPT},
            {
                "role": "user",
                "content": [
                    {"type": "image_url", "image_url": {"url": data_url(jpeg)}}
                ],
            },
        ],
        "label_car",
        "Label the car.",
        LABEL_SCHEMA,
    )
    if not res.args:
        print(f"  label failed for {rec['image_id']}: {res.error}")
        return None
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(res.args))
    return res.args


# --- Descriptions and negatives ---


def describe(
    make: str, model: str, color: str | None, rng: random.Random
) -> tuple[str, str]:
    """Return (description, style) phrased like a rider would type it."""
    shown_make = ALIASES.get(make, make) if rng.random() < 0.5 else make
    styles = (
        ["color_make_model", "make_model", "color_model"]
        if color
        else ["make_model", "model_only"]
    )
    style = rng.choices(styles, weights=[5, 3, 2] if color else [4, 1])[0]
    text = {
        "color_make_model": f"{color} {shown_make} {model}",
        "make_model": f"{shown_make} {model}",
        "color_model": f"{color} {model}",
        "model_only": model,
    }[style]
    return (text.lower() if rng.random() < 0.5 else text), style


def described_attrs(make: str, model: str, color: str | None, style: str) -> dict:
    """The attributes a description actually mentions (None = not mentioned)."""
    return {
        "desc_make": make if style in ("color_make_model", "make_model") else None,
        "desc_model": model,
        "desc_color": color if style in ("color_make_model", "color_model") else None,
    }


def same_model(a: dict, b: dict) -> bool:
    ma, mb = _norm(a["model"]), _norm(b["model"])
    return _norm(a["make"]) == _norm(b["make"]) and (ma in mb or mb in ma)


# Neighboring shades riders and models plausibly confuse; swaps between them are tagged separately.
ADJACENT_COLORS = [
    {"silver", "white"},
    {"silver", "black"},
    {"gray", "black"},
    {"gray", "white"},
    {"beige", "white"},
    {"beige", "gray"},
    {"beige", "silver"},
]


def swap_color(color: str, rng: random.Random) -> str:
    group = COLOR_GROUP.get(color, color)
    return rng.choice([c for c in COMMON_COLORS if COLOR_GROUP.get(c, c) != group])


def build_cases(pool: list[dict], rng: random.Random) -> list[dict]:
    cases = []
    neg_types = ["same_make", "same_body", "color_swap", "random"]
    for i, rec in enumerate(pool):
        color = rec["color"] if rec["color"] != "multicolor" else None
        base = {
            k: rec[k]
            for k in ("image_id", "image_path", "bbox", "source", "view", "body_type")
        }
        base |= {
            "true_make": rec["make"],
            "true_model": rec["model"],
            "true_color": rec["color"],
        }

        pos_color = color if rng.random() < 0.7 else None
        desc, style = describe(rec["make"], rec["model"], pos_color, rng)
        cases.append(
            base
            | {
                "case_id": f"{rec['image_id']}_pos",
                "label": "match",
                "description": desc,
                "desc_style": style,
                "neg_type": None,
            }
            | described_attrs(rec["make"], rec["model"], pos_color, style)
        )

        neg_type = neg_types[i % len(neg_types)]
        others = [o for o in pool if not same_model(o, rec)]
        candidates = {
            "same_make": [o for o in others if _norm(o["make"]) == _norm(rec["make"])],
            "same_body": [
                o
                for o in others
                if o["body_type"] == rec["body_type"]
                and _norm(o["make"]) != _norm(rec["make"])
            ],
            "random": others,
        }
        if neg_type == "color_swap" and color:
            wrong = swap_color(color, rng)
            if {color, wrong} in ADJACENT_COLORS:
                neg_type = "color_swap_adjacent"
            desc, style = describe(rec["make"], rec["model"], wrong, rng)
            if style in (
                "make_model",
                "model_only",
            ):  # color must be present for a color-swap negative
                desc, style = (
                    f"{wrong} {rec['make']} {rec['model']}",
                    "color_make_model",
                )
            neg_attrs = described_attrs(rec["make"], rec["model"], wrong, style)
        else:
            if neg_type == "color_swap" or not candidates.get(neg_type):
                neg_type = "random"
            other = rng.choice(candidates[neg_type])
            # Keep the true color half the time so only make/model differ (harder).
            neg_color = color if rng.random() < 0.5 else None
            desc, style = describe(other["make"], other["model"], neg_color, rng)
            neg_attrs = described_attrs(other["make"], other["model"], neg_color, style)
        cases.append(
            base
            | {
                "case_id": f"{rec['image_id']}_neg",
                "label": "mismatch",
                **neg_attrs,
                "description": desc,
                "desc_style": style,
                "neg_type": neg_type,
            }
        )
    return cases


def is_side(lab: dict) -> bool:
    return lab["view"] == "side"


def cached_label_rates(source: str) -> tuple[float, float] | None:
    """(usable rate, side rate among usable) from labels already cached for this source."""
    labs = [json.loads(p.read_text()) for p in LABEL_CACHE.glob(f"{source}_*.json")]
    usable = [lab for lab in labs if lab["usable"]]
    if len(labs) < 10 or not usable:
        return None
    return len(usable) / len(labs), sum(map(is_side, usable)) / len(usable)


def collect(
    records: list[dict],
    target: int,
    min_side: float,
    cap: int | None,
    budget: list[int],
    rng: random.Random,
    workers: int,
    batch: int = 64,
) -> list[dict]:
    """Label candidates in round-robin model order until `target` usable images with at
    least `min_side` side views are accepted. `budget` is a shared [remaining uncached calls]."""
    side_target = math.ceil(target * min_side)
    other_target = target - side_target
    order = sample_balanced(records, len(records), None, rng)
    accepted: list[dict] = []
    per_model: Counter = Counter()
    n_side = n_other = 0
    i = 0
    with ThreadPoolExecutor(workers) as pool:
        while (n_side < side_target or n_other < other_target) and i < len(order):
            chunk = [
                r
                for r in order[i : i + batch]
                if cap is None or per_model[(r["make"], r["model"])] < cap
            ]
            i += batch
            uncached = sum(
                not (LABEL_CACHE / f"{r['image_id']}.json").exists() for r in chunk
            )
            if uncached > budget[0]:
                print(
                    f"  label budget exhausted ({n_side} side / {n_other} other accepted)"
                )
                break
            budget[0] -= uncached
            for rec, lab in zip(chunk, pool.map(label, chunk)):
                key = (rec["make"], rec["model"])
                if (
                    not lab
                    or not lab["usable"]
                    or (cap is not None and per_model[key] >= cap)
                ):
                    continue
                if is_side(lab) and n_side < side_target:
                    n_side += 1
                elif not is_side(lab) and n_other < other_target:
                    n_other += 1
                else:
                    continue
                per_model[key] += 1
                accepted.append(rec | lab)
    print(f"  accepted {n_side} side + {n_other} other across {len(per_model)} models")
    return accepted


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    ap.add_argument(
        "--counts",
        nargs="+",
        default=["vmmr=600", "stanford=200"],
        help="usable images per source as source=N (2 cases each)",
    )
    ap.add_argument(
        "--min-side",
        type=float,
        default=0.4,
        help="minimum fraction of side-view images",
    )
    ap.add_argument("--out", type=Path, default=DATA_DIR / "realworld_cases.jsonl")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument(
        "--max-requests", type=int, default=60, help="label-call budget unless --yes"
    )
    ap.add_argument(
        "--max-label-calls",
        type=int,
        default=4000,
        help="hard label-call budget with --yes",
    )
    ap.add_argument("--yes", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    rng = random.Random(args.seed)
    counts = {s: int(n) for s, n in (c.split("=") for c in args.counts)}
    sources = {s: LOADERS[s]() for s in counts}

    print(f"Target: >= {args.min_side:.0%} side views per source")
    for source, target in counts.items():
        models = len({(r["make"], r["model"]) for r in sources[source]})
        line = f"{source}: {len(sources[source])} images across {models} models, target {target}"
        if rates := cached_label_rates(source):
            usable, side = rates
            side_t = math.ceil(target * args.min_side)
            est = max(
                side_t / (usable * side), (target - side_t) / (usable * (1 - side))
            )
            line += f" | cached rates: usable {usable:.0%}, side {side:.0%} -> ~{est:.0f} label calls"
        print(line)
    if args.dry_run:
        return

    budget = [args.max_label_calls if args.yes else args.max_requests]
    cases = []
    for source, target in counts.items():
        print(f"{source}:")
        cap = VMMR_MAX_PER_MODEL if source == "vmmr" else None
        recs = collect(
            sources[source], target, args.min_side, cap, budget, rng, args.workers
        )
        if len(recs) < target and not args.yes:
            sys.exit(
                f"Stopped at --max-requests={args.max_requests}. Re-run with --yes after approval."
            )
        print(f"  {len(recs)} images -> {2 * len(recs)} cases")
        cases += build_cases(recs, rng)

    rng.shuffle(cases)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("".join(json.dumps(c) + "\n" for c in cases))
    print(f"Wrote {len(cases)} cases to {args.out}")


if __name__ == "__main__":
    main()
