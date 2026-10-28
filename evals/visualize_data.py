#!/usr/bin/env python3
"""Quick interactive visualization of test data."""

import json
from collections import Counter
from pathlib import Path

def load_data():
    """Load test cases."""
    cases = []
    with open(Path(__file__).parent / "data" / "test_cases.jsonl") as f:
        for line in f:
            cases.append(json.loads(line)["item"])
    return cases

def visualize():
    cases = load_data()
    
    print("=" * 80)
    print("TRAFFICEYE EVAL TEST DATA VISUALIZATION")
    print("=" * 80)
    print(f"\nTotal cases: {len(cases)}\n")
    
    # By decision
    decisions = Counter(c["expected_decision"] for c in cases)
    print("BY DECISION:")
    for decision, count in sorted(decisions.items()):
        bar = "█" * (count // 2)
        print(f"  {decision:10} {count:3} {bar}")
    
    # By test type
    print("\nBY TEST TYPE:")
    types = Counter(c["test_case_type"] for c in cases)
    for test_type, count in sorted(types.items(), key=lambda x: -x[1]):
        bar = "█" * count
        print(f"  {test_type:20} {count:3} {bar}")
    
    # By info quality
    print("\nBY INFO QUALITY:")
    quality = Counter(c["info_quality"] for c in cases)
    for q, count in sorted(quality.items()):
        bar = "█" * (count // 5)
        print(f"  {q:10} {count:3} {bar}")
    
    # Probability distribution
    print("\nPROBABILITY DISTRIBUTION:")
    prob_buckets = {
        "0.0-0.2": 0,
        "0.2-0.4": 0,
        "0.4-0.6": 0,
        "0.6-0.8": 0,
        "0.8-1.0": 0,
    }
    for c in cases:
        prob = c["expected_probability"]
        if prob < 0.2:
            prob_buckets["0.0-0.2"] += 1
        elif prob < 0.4:
            prob_buckets["0.2-0.4"] += 1
        elif prob < 0.6:
            prob_buckets["0.4-0.6"] += 1
        elif prob < 0.8:
            prob_buckets["0.6-0.8"] += 1
        else:
            prob_buckets["0.8-1.0"] += 1
    
    for bucket, count in prob_buckets.items():
        bar = "█" * count
        print(f"  {bucket:10} {count:3} {bar}")
    
    # Sample cases
    print("\n" + "=" * 80)
    print("SAMPLE CASES (3 from each decision type)")
    print("=" * 80)
    
    for decision in ["match", "mismatch", "maybe"]:
        print(f"\n{decision.upper()}:")
        samples = [c for c in cases if c["expected_decision"] == decision][:3]
        for i, sample in enumerate(samples, 1):
            mmr = json.loads(sample["mmr_json"])
            print(f"\n  {i}. {sample['test_case_type']} (prob={sample['expected_probability']})")
            print(f"     API: {mmr['color']['value']} {mmr['make']['value']} {mmr['model']['value']}")
            print(f"     User: {sample['user_description']}")
            print(f"     Scores: make={mmr['make']['score']:.2f}, model={mmr['model']['score']:.2f}, color={mmr['color']['score']:.2f}")

if __name__ == "__main__":
    visualize()
