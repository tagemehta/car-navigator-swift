#!/usr/bin/env python3
"""vehicle_csv_analyzer.py
Quick-and-dirty playground for analysing verifier CSV outputs.

Usage:
  python scripts/vehicle_csv_analyzer.py [path/to/csv]
If no path is given, it automatically picks the most recent CSV in
`results/`.

The script prints:
  • overall make-match %, model-match %, colour-match %
  • average Jaccard similarity between model token sets

Modify SYNONYMS, BODY_WORDS, etc. as you iterate.
"""
from __future__ import annotations

import csv, re, sys, glob, os, difflib, statistics
from pathlib import Path

# ----------------- Configurable dictionaries -----------------
BODY_WORDS = {
    "sedan","coupe","convertible","wagon","hatchback","suv","van","cab",
    "crew","regular","extended","cargo","minivan","roadster","cabriolet",
    "car","truck",
}
TRIM_WORDS = {
    "hybrid","sport","gt","ss","srt","rt","lx","ex","v8","v6","v12",
    "db9","zr1","z06","xkr","xk","touring","supersports","super","gti","hse",
    "awd","ff","xl","xlt","lt","ls","sv","rs","rsx","type","series","class",
}
COLOURS = {
    "black","white","silver","grey","gray","blue","red","green","yellow","gold",
    "orange","brown","beige","maroon","pink","purple","burgundy","tan","teal",
}
# Add or edit as you learn new aliases
SYNONYMS: dict[str,str] = {
    "vw":"volkswagen",
    "volkswagon":"volkswagen",
    "chevy":"chevrolet",
    "mb":"mercedes-benz",
    "mercedes":"mercedes-benz",
    "merc":"mercedes-benz",
    "rr":"rolls-royce",
    "land":"land-rover",
    "rover":"land-rover",
}

# ----------------- Normalisation helpers -----------------

def _tokenise(text: str) -> list[str]:
    """Lowercase, strip punctuation -> tokens."""
    text = text.lower()
    text = re.sub(r"[^a-z0-9 ]", " ", text)
    return text.split()

def normalise(text: str):
    tokens = _tokenise(text)
    tokens = [t for t in tokens if not (len(t) == 4 and t.isdigit())]  # remove years
    colour: str | None = None
    filtered: list[str] = []
    for t in tokens:
        if t in COLOURS and colour is None:
            colour = t
            continue
        if t in BODY_WORDS or t in TRIM_WORDS:
            continue
        filtered.append(t)
    if not filtered:
        return None  # unparseable
    make = SYNONYMS.get(filtered[0], filtered[0])
    model_tokens = filtered[1:]
    return make, model_tokens, colour

def jaccard(a: list[str], b: list[str]) -> float:
    if not a or not b:
        return 0.0
    sa, sb = set(a), set(b)
    return len(sa & sb) / len(sa | sb)

def fuzzy_match(a: list[str], b: list[str], threshold: float = 0.8) -> bool:
    if not a or not b:
        return False
    return difflib.SequenceMatcher(None, " ".join(a), " ".join(b)).ratio() >= threshold

# ----------------- CSV analysis -----------------

def analyse(csv_path: Path):
    total = 0
    make_match = 0
    model_match = 0
    both_match = 0
    colour_match = 0
    j_scores: list[float] = []
    substring_match = 0
    
    # For match analysis
    true_pos = 0
    false_pos = 0
    true_neg = 0
    false_neg = 0
    
    with csv_path.open() as f:
        reader = csv.DictReader(f)
        for row in reader:
            total += 1
            gt = normalise(row["ground_truth"])
            pred = normalise(row["predicted"])
            
            # Get expected and predicted match status
            expected = row.get("expected", "").lower() == 'true'
            is_match = row.get("is_match", "").lower() == 'true'
            
            # Update confusion matrix
            if expected and is_match:
                true_pos += 1
            elif not expected and not is_match:
                true_neg += 1
            elif expected and not is_match:
                false_neg += 1
            elif not expected and is_match:
                false_pos += 1
                
            if not gt or not pred:
                continue
                
            make_ok = gt[0] == pred[0]
            model_ok = fuzzy_match(gt[1], pred[1])
            
            if make_ok:
                make_match += 1
            if model_ok:
                model_match += 1
            if make_ok and model_ok:
                both_match += 1
            if gt[2] and pred[2] and gt[2] == pred[2]:
                colour_match += 1
                
            j_scores.append(jaccard(gt[1], pred[1]))
            
            # Simple substring heuristic
            raw_gt = row["ground_truth"].lower()
            if gt[0] in raw_gt and all(tok in raw_gt for tok in pred[1][:2]):
                substring_match += 1

    # Calculate metrics
    precision = true_pos / (true_pos + false_pos) if (true_pos + false_pos) > 0 else 0
    recall = true_pos / (true_pos + false_neg) if (true_pos + false_neg) > 0 else 0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0
    accuracy = (true_pos + true_neg) / total if total > 0 else 0

    print(f"Analysed {total} rows from {csv_path}")
    print("\n--- Match Metrics ---")
    print(f"Accuracy: {accuracy:.3%}")
    print(f"Precision: {precision:.3%}")
    print(f"Recall: {recall:.3%}")
    print(f"F1 Score: {f1:.3f}")
    print(f"True Positives: {true_pos}")
    print(f"False Positives: {false_pos}")
    print(f"True Negatives: {true_neg}")
    print(f"False Negatives: {false_neg}")
    
    print("\n--- Detailed Accuracy ---")
    print(f"Make accuracy: {make_match/total:.3%}")
    print(f"Model (fuzzy) accuracy: {model_match/total:.3%}")
    print(f"Make + Model accuracy: {both_match/total:.3%}")
    print(f"Colour accuracy (if present): {colour_match/total:.3%}")
    print(f"Average Jaccard(model tokens): {statistics.mean(j_scores):.3f}" if j_scores else "No valid Jaccard scores")
    print(f"Substring heuristic (make + model tokens in GT): {substring_match/total:.3%}" if total > 0 else "No data")

# ----------------- Entry -----------------
if __name__ == "__main__":
    if len(sys.argv) > 1:
        path = Path(sys.argv[1])
    else:
        latest = max(glob.glob("results/twoStep_*.csv"), key=os.path.getmtime)
        path = Path(latest)
    analyse(path)
