#!/usr/bin/env python3
"""
Run TrafficEye MMR comparison eval across multiple models.

Usage:
    python run_eval.py                    # Run all models
    python run_eval.py --models gpt-4.1-mini gpt-5.4-nano  # Run specific models
    python run_eval.py --dry-run          # Show what would be run
"""

import argparse
import json
import time
from pathlib import Path
from trafficeye_comparison_eval import (
    SYSTEM_PROMPT,
    USER_PROMPT_TEMPLATE,
    TOOL_SCHEMA,
    create_eval,
    upload_test_data,
    get_eval_by_name,
    get_client,
)

# Models to evaluate
MODELS = [
    "gpt-5.5",
    "gpt-5.4",
    "gpt-5.4-mini",
    "gpt-5.4-nano",
    "gpt-5-mini",
    "gpt-5-nano",
    "gpt-4.1",
    "gpt-4.1-mini",  # Current production
]

EVAL_NAME = "TrafficEye MMR Comparison"


def create_eval_run(eval_id: str, model: str, file_id: str, run_name: str) -> dict:
    """Create an eval run for a specific model."""

    # Schema for structured output matching production tool call
    output_schema = {
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
    }

    run = get_client().evals.runs.create(
        eval_id,
        name=run_name,
        data_source={
            "type": "responses",
            "model": model,
            "input_messages": {
                "type": "template",
                "template": [
                    {
                        "type": "message",
                        "role": "developer",
                        "content": {"type": "input_text", "text": SYSTEM_PROMPT},
                    },
                    {
                        "type": "message",
                        "role": "user",
                        "content": {"type": "input_text", "text": USER_PROMPT_TEMPLATE},
                    },
                ],
            },
            "source": {"type": "file_id", "id": file_id},
            "sampling_params": {
                "temperature": 0,
                "text": {
                    "format": {
                        "type": "json_schema",
                        "name": "match_decision",
                        "schema": output_schema,
                        "strict": True,
                    },
                },
            },
        },
    )

    return run


def wait_for_run(eval_id: str, run_id: str, poll_interval: int = 10) -> dict:
    """Poll until run completes."""
    while True:
        run = get_client().evals.runs.retrieve(run_id, eval_id=eval_id)
        status = run.status

        if status == "completed":
            return run
        elif status in ["failed", "canceled"]:
            print(f"  Run {status}: {run.error}")
            return run

        print(f"  Status: {status}... waiting {poll_interval}s")
        time.sleep(poll_interval)


def run_all_models(models: list[str], dry_run: bool = False) -> dict:
    """Run eval for all specified models."""

    # Ensure test data exists
    test_data_path = Path(__file__).parent / "data" / "test_cases.jsonl"
    if not test_data_path.exists():
        print("Test data not found. Generating...")
        import generate_test_data

        generate_test_data.main()

    # Get or create eval
    eval_obj = get_eval_by_name(EVAL_NAME)
    if not eval_obj:
        print("Creating eval configuration...")
        eval_obj = create_eval(EVAL_NAME)
    eval_id = eval_obj.id
    print(f"Using eval: {eval_id}")

    # Upload test data
    print(f"Uploading test data from {test_data_path}...")
    if dry_run:
        file_id = "file-DRYRUN"
        print(f"  [DRY RUN] Would upload {test_data_path}")
    else:
        file_id = upload_test_data(str(test_data_path))
        print(f"  Uploaded: {file_id}")

    # Run each model
    results = {}
    for model in models:
        run_name = f"{model} - {time.strftime('%Y-%m-%d %H:%M')}"
        print(f"\nStarting run: {run_name}")

        if dry_run:
            print(f"  [DRY RUN] Would create run for {model}")
            results[model] = {"status": "dry_run"}
            continue

        try:
            run = create_eval_run(eval_id, model, file_id, run_name)
            print(f"  Created run: {run.id}")

            # Wait for completion
            completed_run = wait_for_run(eval_id, run.id)

            results[model] = {
                "run_id": completed_run.id,
                "status": completed_run.status,
                "result_counts": completed_run.result_counts,
                "per_testing_criteria_results": completed_run.per_testing_criteria_results,
                "per_model_usage": completed_run.per_model_usage,
                "report_url": completed_run.report_url,
            }

            # Print summary
            if completed_run.result_counts:
                rc = completed_run.result_counts
                total = getattr(rc, "total", 0)
                passed = getattr(rc, "passed", 0)
                if total > 0:
                    print(
                        f"  Results: {passed}/{total} passed ({100 * passed / total:.1f}%)"
                    )

        except Exception as e:
            print(f"  Error: {e}")
            results[model] = {"status": "error", "error": str(e)}

    # Save results
    results_path = Path(__file__).parent / "results" / "eval_runs.json"
    results_path.parent.mkdir(exist_ok=True)
    with open(results_path, "w") as f:
        json.dump(results, f, indent=2, default=str)
    print(f"\nResults saved to: {results_path}")

    return results


def main():
    parser = argparse.ArgumentParser(description="Run TrafficEye MMR comparison eval")
    parser.add_argument(
        "--models", nargs="+", default=MODELS, help="Models to evaluate"
    )
    parser.add_argument("--dry-run", action="store_true", help="Show what would be run")
    args = parser.parse_args()

    print("=" * 60)
    print("TrafficEye MMR Comparison Eval")
    print("=" * 60)
    print(f"Models: {', '.join(args.models)}")
    print()

    results = run_all_models(args.models, dry_run=args.dry_run)

    # Print summary table
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"{'Model':<20} {'Status':<12} {'Passed':<10} {'Accuracy':<10}")
    print("-" * 60)

    for model, data in results.items():
        status = data.get("status", "unknown")
        if status == "completed" and data.get("result_counts"):
            rc = data["result_counts"]
            passed = getattr(rc, "passed", 0)
            total = getattr(rc, "total", 1)
            accuracy = f"{100 * passed / total:.1f}%"
            print(f"{model:<20} {status:<12} {passed:<10} {accuracy:<10}")
        else:
            print(f"{model:<20} {status:<12} {'N/A':<10} {'N/A':<10}")


if __name__ == "__main__":
    main()
