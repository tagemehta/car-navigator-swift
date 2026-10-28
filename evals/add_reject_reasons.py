#!/usr/bin/env python3
"""Add expected_reject_reason to existing test cases."""

import json
from pathlib import Path


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


def main():
    input_path = Path(__file__).parent / "data" / "test_cases.jsonl"
    output_path = Path(__file__).parent / "data" / "test_cases_updated.jsonl"
    
    updated_cases = []
    with open(input_path) as f:
        for line in f:
            data = json.loads(line)
            item = data["item"]
            
            # Parse MMR to compute info quality
            mmr = json.loads(item["mmr_json"])
            info_quality, info_score = compute_info_quality(mmr)
            
            # Add new fields
            item["expected_reject_reason"] = compute_reject_reason(
                item["expected_decision"], info_quality
            )
            item["info_score"] = round(info_score, 4)
            
            # Update info_quality if it changed
            item["info_quality"] = info_quality
            
            updated_cases.append({"item": item})
    
    # Write updated cases
    with open(output_path, "w") as f:
        for case in updated_cases:
            f.write(json.dumps(case) + "\n")
    
    # Replace original
    output_path.replace(input_path)
    
    print(f"Updated {len(updated_cases)} test cases with expected_reject_reason")
    
    # Show sample
    sample = updated_cases[0]["item"]
    print(f"\nSample case:")
    print(f"  Decision: {sample['expected_decision']}")
    print(f"  Info quality: {sample['info_quality']} ({sample['info_score']})")
    print(f"  Expected reject reason: {sample['expected_reject_reason']}")


if __name__ == "__main__":
    main()
