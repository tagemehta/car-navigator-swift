#!/usr/bin/env python3
"""
Generate synthetic test data for TrafficEye MMR to user description comparison eval.

Creates ~150 test cases covering:
- Match cases (40%): exact, color equivalents, abbreviations, extra API info
- Mismatch cases (30%): wrong make, wrong model, wrong color
- Maybe cases (30%): low confidence, partial info, ambiguous
"""

import json
import random
from pathlib import Path

# TrafficEye API color palette
TRAFFICEYE_COLORS = [
    "BLUE",
    "BROWN",
    "YELLOW",
    "GRAY",
    "GREEN",
    "PURPLE",
    "RED",
    "WHITE",
    "BLACK",
    "ORANGE",
]

# Color equivalents that should be treated as matches
COLOR_EQUIVALENTS = {
    "GRAY": ["gray", "grey", "silver", "charcoal"],
    "WHITE": ["white", "cream", "ivory", "pearl"],
    "BLACK": ["black", "dark", "midnight"],
    "BLUE": ["blue", "navy", "cobalt", "azure"],
    "RED": ["red", "maroon", "burgundy", "crimson"],
    "GREEN": ["green", "olive", "forest", "lime"],
    "BROWN": ["brown", "tan", "beige", "bronze"],
    "ORANGE": ["orange", "copper", "rust"],
    "YELLOW": ["yellow", "gold", "golden"],
    "PURPLE": ["purple", "violet", "plum"],
}

# Common vehicle makes and their abbreviations
MAKES = {
    "Honda": ["Honda", "honda"],
    "Toyota": ["Toyota", "toyota"],
    "Ford": ["Ford", "ford"],
    "Chevrolet": ["Chevrolet", "Chevy", "chevy", "chevrolet"],
    "BMW": ["BMW", "bmw"],
    "Mercedes-Benz": ["Mercedes-Benz", "Mercedes", "Benz", "mercedes"],
    "Nissan": ["Nissan", "nissan"],
    "Hyundai": ["Hyundai", "hyundai"],
    "Kia": ["Kia", "kia"],
    "Volkswagen": ["Volkswagen", "VW", "vw"],
    "Subaru": ["Subaru", "subaru"],
    "Mazda": ["Mazda", "mazda"],
    "Tesla": ["Tesla", "tesla"],
    "Jeep": ["Jeep", "jeep"],
    "Lexus": ["Lexus", "lexus"],
}

# Models by make
MODELS = {
    "Honda": ["Civic", "Accord", "CR-V", "Pilot", "HR-V", "Odyssey"],
    "Toyota": ["Camry", "Corolla", "RAV4", "Highlander", "Prius", "Tacoma"],
    "Ford": ["F-150", "Mustang", "Explorer", "Escape", "Bronco", "Focus"],
    "Chevrolet": ["Silverado", "Malibu", "Equinox", "Tahoe", "Camaro", "Traverse"],
    "BMW": ["3 Series", "5 Series", "X3", "X5", "M3", "i4"],
    "Mercedes-Benz": ["C-Class", "E-Class", "GLC", "GLE", "S-Class", "A-Class"],
    "Nissan": ["Altima", "Sentra", "Rogue", "Pathfinder", "Maxima", "Frontier"],
    "Hyundai": ["Elantra", "Sonata", "Tucson", "Santa Fe", "Kona", "Palisade"],
    "Kia": ["Forte", "K5", "Sportage", "Sorento", "Telluride", "Soul"],
    "Volkswagen": ["Jetta", "Passat", "Tiguan", "Atlas", "Golf", "ID.4"],
    "Subaru": ["Outback", "Forester", "Crosstrek", "Impreza", "Legacy", "Ascent"],
    "Mazda": ["Mazda3", "Mazda6", "CX-5", "CX-9", "MX-5", "CX-30"],
    "Tesla": ["Model 3", "Model Y", "Model S", "Model X", "Cybertruck"],
    "Jeep": ["Wrangler", "Grand Cherokee", "Cherokee", "Compass", "Gladiator"],
    "Lexus": ["ES", "RX", "NX", "IS", "GX", "UX"],
}

# View options
VIEWS = ["frontal", "rear", "side"]
VIEW8_OPTIONS = [
    "frontal exact",
    "frontal+left",
    "frontal+right",
    "rear exact",
    "rear+left",
    "rear+right",
    "left",
    "right",
]


def generate_mmr(
    make: str,
    model: str,
    color: str,
    make_score: float = 0.99,
    model_score: float = 0.99,
    color_score: float = 0.99,
    view: str = "frontal",
) -> dict:
    """Generate MMR JSON in TrafficEye format."""
    view8 = random.choice([
        v
        for v in VIEW8_OPTIONS
        if view in v.lower() or (view == "side" and v in ["left", "right"])
    ])

    return {
        "make": {"value": make, "score": round(make_score, 4)},
        "model": {"value": model, "score": round(model_score, 4)},
        "color": {"value": color, "score": round(color_score, 4)},
        "view": {"value": view, "score": round(random.uniform(0.95, 0.9999), 4)},
        "view8": {"value": view8, "score": round(random.uniform(0.95, 0.9999), 4)},
    }


def compute_info_quality(mmr: dict) -> tuple[str, float]:
    """Compute info quality level based on weighted scores."""
    make_score = mmr["make"]["score"]
    model_score = mmr["model"]["score"]
    color_score = mmr["color"]["score"]
    weighted = 0.5 * make_score + 0.3 * model_score + 0.2 * color_score
    if weighted >= 0.85:
        return "high", weighted
    elif weighted >= 0.4:
        return "medium", weighted
    return "low", weighted


def compute_reject_reason(semantic_reason: str, info_quality: str) -> str:
    """Map semantic_reason + info_quality to RejectReason (matching TrafficEyeVerifier logic)."""
    if info_quality == "high":
        if semantic_reason == "match":
            return "success"
        elif semantic_reason == "maybe":
            return "low_confidence"
        else:  # mismatch
            return "wrong_model_or_color"
    else:  # medium or low quality
        if semantic_reason == "match":
            return "success"
        else:
            return "insufficient_info"


def create_test_case(
    mmr: dict,
    user_desc: str,
    expected_decision: str,
    expected_probability: float,
    test_case_type: str,
) -> dict:
    """Helper to create a test case with all required fields."""
    info_quality, info_score = compute_info_quality(mmr)
    expected_reject_reason = compute_reject_reason(expected_decision, info_quality)

    return {
        "mmr_json": json.dumps(mmr),
        "user_description": user_desc,
        "expected_decision": expected_decision,
        "expected_probability": expected_probability,
        "expected_reject_reason": expected_reject_reason,
        "info_quality": info_quality,
        "info_score": round(info_score, 4),
        "test_case_type": test_case_type,
    }


def generate_match_cases() -> list:
    """Generate match test cases (40% of total)."""
    cases = []

    # Exact matches
    for _ in range(15):
        make = random.choice(list(MAKES.keys()))
        model = random.choice(MODELS[make])
        color = random.choice(TRAFFICEYE_COLORS)
        user_color = random.choice(COLOR_EQUIVALENTS[color]).lower()

        mmr = generate_mmr(make, model, color)
        user_desc = f"{user_color} {make} {model}"

        info_quality, info_score = compute_info_quality(mmr)
        expected_decision = "match"
        expected_reject_reason = compute_reject_reason(expected_decision, info_quality)

        cases.append({
            "mmr_json": json.dumps(mmr),
            "user_description": user_desc,
            "expected_decision": expected_decision,
            "expected_probability": 0.95,
            "expected_reject_reason": expected_reject_reason,
            "info_quality": info_quality,
            "info_score": round(info_score, 4),
            "test_case_type": "exact_match",
        })

    # Color equivalents (silver/gray, etc.)
    for _ in range(10):
        make = random.choice(list(MAKES.keys()))
        model = random.choice(MODELS[make])
        color = random.choice(["GRAY", "WHITE", "BLACK"])
        user_color = random.choice(COLOR_EQUIVALENTS[color])

        mmr = generate_mmr(make, model, color)
        user_desc = f"{user_color} {make} {model}"

        cases.append({
            "mmr_json": json.dumps(mmr),
            "user_description": user_desc,
            "expected_decision": "match",
            "expected_probability": 0.88,
            "info_quality": compute_info_quality(mmr),
            "test_case_type": "color_variation",
        })

    # Abbreviations (Chevy, VW, Mercedes)
    abbrev_makes = ["Chevrolet", "Volkswagen", "Mercedes-Benz"]
    for _ in range(10):
        make = random.choice(abbrev_makes)
        model = random.choice(MODELS[make])
        color = random.choice(TRAFFICEYE_COLORS)
        user_make = random.choice([m for m in MAKES[make] if m != make])

        mmr = generate_mmr(make, model, color)
        user_desc = f"{color.lower()} {user_make} {model}"

        cases.append({
            "mmr_json": json.dumps(mmr),
            "user_description": user_desc,
            "expected_decision": "match",
            "expected_probability": 0.90,
            "info_quality": compute_info_quality(mmr),
            "test_case_type": "abbreviation",
        })

    # Extra API info (API has color, user doesn't mention it) - MATCH
    for _ in range(10):
        make = random.choice(list(MAKES.keys()))
        model = random.choice(MODELS[make])
        color = random.choice(TRAFFICEYE_COLORS)

        mmr = generate_mmr(make, model, color)
        user_desc = f"{make} {model}"  # No color

        cases.append({
            "mmr_json": json.dumps(mmr),
            "user_description": user_desc,
            "expected_decision": "match",
            "expected_probability": 0.90,  # High confidence - make+model match
            "info_quality": compute_info_quality(mmr),
            "test_case_type": "extra_api_info",
        })

    # Model with trim level (API: Civic LX, User: Civic)
    for _ in range(10):
        make = random.choice(list(MAKES.keys()))
        model = random.choice(MODELS[make])
        color = random.choice(TRAFFICEYE_COLORS)
        trim = random.choice(["LX", "EX", "Sport", "Limited", "SE", "XLE"])

        mmr = generate_mmr(make, f"{model} {trim}", color)
        user_desc = f"{color.lower()} {make} {model}"

        cases.append({
            "mmr_json": json.dumps(mmr),
            "user_description": user_desc,
            "expected_decision": "match",
            "expected_probability": 0.85,
            "info_quality": compute_info_quality(mmr),
            "test_case_type": "model_trim",
        })

    return cases


def generate_mismatch_cases() -> list:
    """Generate mismatch test cases (30% of total)."""
    cases = []

    # Wrong make
    for _ in range(15):
        make1, make2 = random.sample(list(MAKES.keys()), 2)
        model = random.choice(MODELS[make1])
        color = random.choice(TRAFFICEYE_COLORS)

        mmr = generate_mmr(make1, model, color)
        user_desc = f"{color.lower()} {make2} {random.choice(MODELS[make2])}"

        cases.append({
            "mmr_json": json.dumps(mmr),
            "user_description": user_desc,
            "expected_decision": "mismatch",
            "expected_probability": 0.10,
            "info_quality": compute_info_quality(mmr),
            "test_case_type": "wrong_make",
        })

    # Wrong model (same make)
    for _ in range(15):
        make = random.choice(list(MAKES.keys()))
        model1, model2 = random.sample(MODELS[make], 2)
        color = random.choice(TRAFFICEYE_COLORS)

        mmr = generate_mmr(make, model1, color)
        user_desc = f"{color.lower()} {make} {model2}"

        cases.append({
            "mmr_json": json.dumps(mmr),
            "user_description": user_desc,
            "expected_decision": "mismatch",
            "expected_probability": 0.20,
            "info_quality": compute_info_quality(mmr),
            "test_case_type": "wrong_model",
        })

    # Wrong color (explicit mismatch)
    for _ in range(10):
        make = random.choice(list(MAKES.keys()))
        model = random.choice(MODELS[make])
        color1, color2 = random.sample(TRAFFICEYE_COLORS, 2)
        # Ensure they're not equivalent
        while any(
            c in COLOR_EQUIVALENTS.get(color1, [])
            for c in COLOR_EQUIVALENTS.get(color2, [])
        ):
            color1, color2 = random.sample(TRAFFICEYE_COLORS, 2)

        mmr = generate_mmr(make, model, color1)
        user_desc = f"{color2.lower()} {make} {model}"

        cases.append({
            "mmr_json": json.dumps(mmr),
            "user_description": user_desc,
            "expected_decision": "mismatch",
            "expected_probability": 0.25,
            "info_quality": compute_info_quality(mmr),
            "test_case_type": "wrong_color",
        })

    return cases


def generate_maybe_cases() -> list:
    """Generate maybe/uncertain test cases (30% of total)."""
    cases = []

    # Low confidence scores - but still a match if descriptions align
    for _ in range(15):
        make = random.choice(list(MAKES.keys()))
        model = random.choice(MODELS[make])
        color = random.choice(TRAFFICEYE_COLORS)

        # Low confidence on one or more attributes
        make_score = random.uniform(0.3, 0.6)
        model_score = random.uniform(0.3, 0.6)
        color_score = random.uniform(0.5, 0.8)

        mmr = generate_mmr(make, model, color, make_score, model_score, color_score)
        user_desc = f"{color.lower()} {make} {model}"

        # Low API confidence doesn't change the semantic match - still a match, just lower probability
        cases.append({
            "mmr_json": json.dumps(mmr),
            "user_description": user_desc,
            "expected_decision": "match",
            "expected_probability": 0.65,  # Lower than high-confidence matches, but still a match
            "info_quality": compute_info_quality(mmr),
            "test_case_type": "low_api_confidence",
        })

    # Partial user info (user only provides make) - MATCH since API has more detail
    for _ in range(10):
        make = random.choice(list(MAKES.keys()))
        model = random.choice(MODELS[make])
        color = random.choice(TRAFFICEYE_COLORS)

        mmr = generate_mmr(make, model, color)
        user_desc = f"{make}"  # Only make, no model or color

        cases.append({
            "mmr_json": json.dumps(mmr),
            "user_description": user_desc,
            "expected_decision": "match",
            "expected_probability": 0.75,  # Lower confidence - only make matches
            "info_quality": compute_info_quality(mmr),
            "test_case_type": "partial_user_info",
        })

    # Similar models (could be either)
    similar_models = [
        ("Honda", "Civic", "Accord"),
        ("Toyota", "Camry", "Corolla"),
        ("Ford", "Escape", "Explorer"),
        ("Chevrolet", "Malibu", "Impala"),
        ("BMW", "3 Series", "5 Series"),
    ]
    for _ in range(10):
        make, model1, model2 = random.choice(similar_models)
        color = random.choice(TRAFFICEYE_COLORS)

        # Low model confidence
        mmr = generate_mmr(make, model1, color, model_score=random.uniform(0.4, 0.6))
        user_desc = f"{color.lower()} {make} {model2}"

        cases.append({
            "mmr_json": json.dumps(mmr),
            "user_description": user_desc,
            "expected_decision": "maybe",
            "expected_probability": 0.45,
            "info_quality": compute_info_quality(mmr),
            "test_case_type": "model_similarity",
        })

    # Color shade variations (dark blue, light gray) - MATCH since API only returns base colors
    for _ in range(10):
        make = random.choice(list(MAKES.keys()))
        model = random.choice(MODELS[make])
        color = random.choice(["GRAY", "BLUE", "GREEN", "RED"])

        mmr = generate_mmr(make, model, color)
        # User adds shade descriptor - still a match since API can't detect shades
        shade = random.choice(["dark", "light", "metallic", "bright"])
        user_desc = f"{shade} {color.lower()} {make} {model}"

        cases.append({
            "mmr_json": json.dumps(mmr),
            "user_description": user_desc,
            "expected_decision": "match",
            "expected_probability": 0.88,  # High confidence - base color matches
            "info_quality": compute_info_quality(mmr),
            "test_case_type": "color_shade_match",
        })

    return cases


def main():
    """Generate all test cases and save to JSONL."""
    random.seed(42)  # Reproducibility

    all_cases = []
    all_cases.extend(generate_match_cases())
    all_cases.extend(generate_mismatch_cases())
    all_cases.extend(generate_maybe_cases())

    # Shuffle
    random.shuffle(all_cases)

    # Save to JSONL (OpenAI Evals format)
    output_path = Path(__file__).parent / "data" / "test_cases.jsonl"
    with open(output_path, "w") as f:
        for case in all_cases:
            f.write(json.dumps({"item": case}) + "\n")

    # Save metadata
    metadata = {
        "total_cases": len(all_cases),
        "by_decision": {
            "match": len([c for c in all_cases if c["expected_decision"] == "match"]),
            "mismatch": len([
                c for c in all_cases if c["expected_decision"] == "mismatch"
            ]),
            "maybe": len([c for c in all_cases if c["expected_decision"] == "maybe"]),
        },
        "by_type": {},
        "by_quality": {
            "high": len([c for c in all_cases if c["info_quality"] == "high"]),
            "medium": len([c for c in all_cases if c["info_quality"] == "medium"]),
            "low": len([c for c in all_cases if c["info_quality"] == "low"]),
        },
    }
    for case in all_cases:
        t = case["test_case_type"]
        metadata["by_type"][t] = metadata["by_type"].get(t, 0) + 1

    metadata_path = Path(__file__).parent / "data" / "test_cases_metadata.json"
    with open(metadata_path, "w") as f:
        json.dump(metadata, f, indent=2)

    print(f"Generated {len(all_cases)} test cases")
    print(f"  Match: {metadata['by_decision']['match']}")
    print(f"  Mismatch: {metadata['by_decision']['mismatch']}")
    print(f"  Maybe: {metadata['by_decision']['maybe']}")
    print(f"\nSaved to: {output_path}")
    print(f"Metadata: {metadata_path}")


if __name__ == "__main__":
    main()
