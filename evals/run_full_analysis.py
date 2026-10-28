#!/usr/bin/env python3
"""Run full evaluation and comprehensive metrics analysis."""

import json
import pandas as pd
import numpy as np
from pathlib import Path
from openai import OpenAI
from typing import Dict, List
import time
from collections import Counter
import sys


def load_api_key():
    """Load API key from Secrets.xcconfig."""
    xcconfig_path = Path(__file__).parent.parent / "thing-finder" / "Secrets.xcconfig"
    if xcconfig_path.exists():
        with open(xcconfig_path) as f:
            for line in f:
                if line.startswith("OPENAI_API"):
                    parts = line.split("=", 1)
                    if len(parts) == 2:
                        return parts[1].strip()
    raise ValueError("API key not found in Secrets.xcconfig")


def load_test_cases():
    """Load test cases from JSONL."""
    cases = []
    with open(Path(__file__).parent / "data" / "test_cases.jsonl") as f:
        for line in f:
            cases.append(json.loads(line)["item"])
    return cases


SYSTEM_PROMPT = """You are a vehicle verification assistant. Your task is to determine if a machine learning model's prediction about a vehicle (make, model, color) matches what the user described.

You will receive:
1. MMR (Make-Model-Recognition) API output with confidence scores
2. User's natural language description of their vehicle

Your job:
- Compare the API prediction with the user's description
- Account for:
  * Color variations (silver/gray, white/cream are similar)
  * Abbreviations (Chevy = Chevrolet, VW = Volkswagen)
  * Model trims (Civic LX vs Civic)
  * Partial user info (user says "Honda" but API says "Red Honda Civic" is still a match)
- Consider confidence scores in MMR output

Decision guidelines:
- **match**: Confident they refer to the same vehicle
- **mismatch**: Confident they are different vehicles (wrong make, model, or color)
- **maybe**: Uncertain due to low confidence scores, ambiguous info, or missing details"""


def create_user_prompt(mmr_json: str, user_description: str) -> str:
    return f"""MMR API Output:
{mmr_json}

User Description: "{user_description}"

Does the API prediction match the user's vehicle?"""


TOOL_SCHEMA = {
    "type": "function",
    "function": {
        "name": "submit_match_decision",
        "description": "Submit the verification probability and justification.",
        "parameters": {
            "type": "object",
            "properties": {
                "probability_match": {
                    "type": "number",
                    "description": "Estimated probability (0-1) that the ML prediction refers to the same car as described by the user.",
                },
                "semantic_reason": {
                    "type": "string",
                    "description": "Match if confident they are the same car. Mismatch if confident they are different. Maybe when uncertain or info is missing.",
                    "enum": ["match", "maybe", "mismatch"],
                },
            },
            "required": ["probability_match", "semantic_reason"],
            "additionalProperties": False,
        },
        "strict": True,
    },
}


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


def run_single_case(client: OpenAI, mmr_json: str, user_description: str, model: str) -> Dict:
    """Run a single test case through the LLM."""
    try:
        response = client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": SYSTEM_PROMPT},
                {"role": "user", "content": create_user_prompt(mmr_json, user_description)},
            ],
            tools=[TOOL_SCHEMA],
            tool_choice="required",
            temperature=0,
        )
        
        # Parse tool call
        tool_call = response.choices[0].message.tool_calls[0]
        args = json.loads(tool_call.function.arguments)
        
        return {
            "semantic_reason": args["semantic_reason"],
            "probability_match": args["probability_match"],
            "tokens_used": response.usage.total_tokens,
            "prompt_tokens": response.usage.prompt_tokens,
            "completion_tokens": response.usage.completion_tokens,
            "error": None,
        }
    except Exception as e:
        return {
            "semantic_reason": None,
            "probability_match": None,
            "tokens_used": 0,
            "prompt_tokens": 0,
            "completion_tokens": 0,
            "error": str(e),
        }


def grade_result(test_case: Dict, result: Dict) -> Dict:
    """Grade a single result against expected values."""
    if result["error"]:
        return {
            "correct_decision": False,
            "correct_reject_reason": False,
            "probability_error": None,
            "actual_reject_reason": None,
        }
    
    # Check semantic_reason
    correct_decision = result["semantic_reason"] == test_case["expected_decision"]
    
    # Compute actual reject_reason from result + info_quality
    actual_reject_reason = compute_reject_reason(
        result["semantic_reason"], test_case["info_quality"]
    )
    correct_reject_reason = actual_reject_reason == test_case["expected_reject_reason"]
    
    # Probability error
    prob_error = abs(result["probability_match"] - test_case["expected_probability"])
    
    return {
        "correct_decision": correct_decision,
        "correct_reject_reason": correct_reject_reason,
        "probability_error": prob_error,
        "actual_reject_reason": actual_reject_reason,
    }


def run_evaluation(client: OpenAI, test_cases: List[Dict], model: str) -> pd.DataFrame:
    """Run evaluation on all test cases."""
    results = []
    
    print(f"\n{'='*80}")
    print(f"Running evaluation: {model}")
    print(f"{'='*80}")
    print(f"Total cases: {len(test_cases)}")
    
    for i, test_case in enumerate(test_cases, 1):
        if i % 20 == 0:
            print(f"  Progress: {i}/{len(test_cases)} ({i/len(test_cases)*100:.0f}%)")
        
        # Run LLM
        result = run_single_case(
            client,
            test_case["mmr_json"],
            test_case["user_description"],
            model=model,
        )
        
        # Grade
        grading = grade_result(test_case, result)
        
        # Combine
        results.append({
            "test_case_type": test_case["test_case_type"],
            "info_quality": test_case["info_quality"],
            "info_score": test_case["info_score"],
            "user_description": test_case["user_description"],
            "mmr_json": test_case["mmr_json"],
            "expected_decision": test_case["expected_decision"],
            "expected_probability": test_case["expected_probability"],
            "expected_reject_reason": test_case["expected_reject_reason"],
            "actual_decision": result["semantic_reason"],
            "actual_probability": result["probability_match"],
            "actual_reject_reason": grading.get("actual_reject_reason"),
            "correct_decision": grading["correct_decision"],
            "correct_reject_reason": grading["correct_reject_reason"],
            "probability_error": grading["probability_error"],
            "tokens_used": result["tokens_used"],
            "prompt_tokens": result["prompt_tokens"],
            "completion_tokens": result["completion_tokens"],
            "error": result["error"],
        })
        
        # Rate limit
        time.sleep(0.05)
    
    df = pd.DataFrame(results)
    print(f"\n✓ Completed {len(df)} cases")
    return df


def compute_metrics(df: pd.DataFrame) -> Dict:
    """Compute comprehensive evaluation metrics."""
    # Filter out errors
    valid_df = df[df["error"].isna()].copy()
    
    if len(valid_df) == 0:
        return {"error": "No valid results"}
    
    metrics = {
        # Overall
        "total_cases": len(df),
        "errors": len(df) - len(valid_df),
        "error_rate": (len(df) - len(valid_df)) / len(df),
        
        # Accuracy
        "decision_accuracy": valid_df["correct_decision"].mean(),
        "reject_reason_accuracy": valid_df["correct_reject_reason"].mean(),
        
        # Probability metrics
        "probability_mae": valid_df["probability_error"].mean(),
        "probability_rmse": np.sqrt((valid_df["probability_error"] ** 2).mean()),
        "probability_median_error": valid_df["probability_error"].median(),
        
        # Token usage
        "total_tokens": valid_df["tokens_used"].sum(),
        "avg_tokens_per_case": valid_df["tokens_used"].mean(),
        "total_prompt_tokens": valid_df["prompt_tokens"].sum(),
        "total_completion_tokens": valid_df["completion_tokens"].sum(),
        
        # By decision type
        "match_precision": (
            valid_df[valid_df["actual_decision"] == "match"]["correct_decision"].mean()
            if len(valid_df[valid_df["actual_decision"] == "match"]) > 0 else 0
        ),
        "mismatch_precision": (
            valid_df[valid_df["actual_decision"] == "mismatch"]["correct_decision"].mean()
            if len(valid_df[valid_df["actual_decision"] == "mismatch"]) > 0 else 0
        ),
        "maybe_precision": (
            valid_df[valid_df["actual_decision"] == "maybe"]["correct_decision"].mean()
            if len(valid_df[valid_df["actual_decision"] == "maybe"]) > 0 else 0
        ),
        
        # Confusion matrix counts
        "confusion_matrix": {
            str(expected): {str(actual): int(n) for actual, n in row.items() if n}
            for expected, row in valid_df.groupby(["expected_decision", "actual_decision"])
            .size()
            .unstack(fill_value=0)
            .iterrows()
        },
    }
    
    return metrics


def print_metrics(metrics: Dict, model: str):
    """Pretty print metrics."""
    print(f"\n{'='*80}")
    print(f"METRICS: {model}")
    print(f"{'='*80}")
    
    if "error" in metrics:
        print(f"ERROR: {metrics['error']}")
        return
    
    print(f"\n📊 OVERALL")
    print(f"  Total cases:              {metrics['total_cases']}")
    print(f"  Errors:                   {metrics['errors']} ({metrics['error_rate']:.1%})")
    
    print(f"\n✅ ACCURACY")
    print(f"  Decision accuracy:        {metrics['decision_accuracy']:.1%}")
    print(f"  Reject reason accuracy:   {metrics['reject_reason_accuracy']:.1%}")
    
    print(f"\n📈 PROBABILITY METRICS")
    print(f"  MAE:                      {metrics['probability_mae']:.3f}")
    print(f"  RMSE:                     {metrics['probability_rmse']:.3f}")
    print(f"  Median error:             {metrics['probability_median_error']:.3f}")
    
    print(f"\n🔢 PRECISION BY DECISION")
    print(f"  Match:                    {metrics['match_precision']:.1%}")
    print(f"  Mismatch:                 {metrics['mismatch_precision']:.1%}")
    print(f"  Maybe:                    {metrics['maybe_precision']:.1%}")
    
    print(f"\n💰 TOKEN USAGE")
    print(f"  Total tokens:             {metrics['total_tokens']:,}")
    print(f"  Avg per case:             {metrics['avg_tokens_per_case']:.0f}")
    print(f"  Prompt tokens:            {metrics['total_prompt_tokens']:,}")
    print(f"  Completion tokens:        {metrics['total_completion_tokens']:,}")
    
    print(f"\n{'='*80}")


def analyze_by_type(df: pd.DataFrame) -> pd.DataFrame:
    """Analyze metrics by test case type."""
    valid_df = df[df["error"].isna()].copy()
    
    by_type = valid_df.groupby("test_case_type").agg({
        "correct_decision": ["mean", "sum", "count"],
        "correct_reject_reason": "mean",
        "probability_error": "mean",
    }).round(3)
    
    by_type.columns = ["decision_acc", "correct_count", "total", "reject_acc", "prob_mae"]
    by_type = by_type.sort_values("decision_acc", ascending=False)
    
    return by_type


def analyze_failures(df: pd.DataFrame, n: int = 10) -> List[Dict]:
    """Get worst failures."""
    failures = df[~df["correct_decision"] & df["error"].isna()].copy()
    failures = failures.sort_values("probability_error", ascending=False)
    
    failure_list = []
    for _, row in failures.head(n).iterrows():
        mmr = json.loads(row["mmr_json"])
        failure_list.append({
            "test_case_type": row["test_case_type"],
            "info_quality": row["info_quality"],
            "api_description": f"{mmr['color']['value']} {mmr['make']['value']} {mmr['model']['value']}",
            "user_description": row["user_description"],
            "expected_decision": row["expected_decision"],
            "expected_probability": row["expected_probability"],
            "actual_decision": row["actual_decision"],
            "actual_probability": row["actual_probability"],
            "expected_reject_reason": row["expected_reject_reason"],
            "actual_reject_reason": row["actual_reject_reason"],
            "probability_error": row["probability_error"],
        })
    
    return failure_list


def main():
    """Run full analysis."""
    # Setup
    api_key = load_api_key()
    client = OpenAI(api_key=api_key)
    test_cases = load_test_cases()
    
    print(f"Loaded {len(test_cases)} test cases")
    
    # Models to test
    models = ["gpt-4.1-mini"]
    if len(sys.argv) > 1:
        models = sys.argv[1].split(",")
    
    results_dir = Path(__file__).parent / "results"
    results_dir.mkdir(exist_ok=True)
    
    all_results = {}
    
    for model in models:
        # Run evaluation
        df = run_evaluation(client, test_cases, model)
        
        # Compute metrics
        metrics = compute_metrics(df)
        print_metrics(metrics, model)
        
        # Analyze by type
        print(f"\n📋 ACCURACY BY TEST TYPE:")
        by_type = analyze_by_type(df)
        print(by_type.to_string())
        
        # Show failures
        print(f"\n❌ TOP 10 FAILURES:")
        failures = analyze_failures(df, n=10)
        for i, failure in enumerate(failures, 1):
            print(f"\n{i}. {failure['test_case_type']} (quality={failure['info_quality']})")
            print(f"   API: {failure['api_description']}")
            print(f"   User: {failure['user_description']}")
            print(f"   Expected: {failure['expected_decision']} (prob={failure['expected_probability']})")
            print(f"   Actual: {failure['actual_decision']} (prob={failure['actual_probability']:.2f})")
            print(f"   Reject reason: expected={failure['expected_reject_reason']}, actual={failure['actual_reject_reason']}")
            print(f"   Probability error: {failure['probability_error']:.3f}")
        
        # Save results
        df.to_csv(results_dir / f"{model}_results.csv", index=False)
        with open(results_dir / f"{model}_metrics.json", "w") as f:
            json.dump(metrics, f, indent=2, default=str)
        
        all_results[model] = {
            "df": df,
            "metrics": metrics,
        }
        
        print(f"\n✓ Results saved to {results_dir}/{model}_results.csv")
    
    # Model comparison if multiple models
    if len(models) > 1:
        print(f"\n{'='*80}")
        print("MODEL COMPARISON")
        print(f"{'='*80}")
        
        comparison = pd.DataFrame({
            model: data["metrics"]
            for model, data in all_results.items()
        }).T
        
        print(comparison[["decision_accuracy", "reject_reason_accuracy", "probability_mae", "total_tokens"]])
        
        comparison.to_csv(results_dir / "model_comparison.csv")
        print(f"\n✓ Comparison saved to {results_dir}/model_comparison.csv")


if __name__ == "__main__":
    main()
