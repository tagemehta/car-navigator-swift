#!/usr/bin/env python3
"""
Analyze eval results and generate comparison report.

Usage:
    python analyze_results.py                    # Analyze latest results
    python analyze_results.py --output report   # Generate markdown report
"""

import argparse
import json
from pathlib import Path
from openai import OpenAI

client = OpenAI()


def load_results() -> dict:
    """Load eval run results."""
    results_path = Path(__file__).parent / "results" / "eval_runs.json"
    if not results_path.exists():
        raise FileNotFoundError(f"No results found at {results_path}. Run eval first.")
    
    with open(results_path) as f:
        return json.load(f)


def fetch_run_details(eval_id: str, run_id: str) -> dict:
    """Fetch detailed results for a run."""
    run = client.evals.runs.retrieve(eval_id, run_id)
    return run


def analyze_results(results: dict) -> dict:
    """Analyze results across all models."""
    analysis = {
        "models": {},
        "best_overall": None,
        "best_accuracy": 0,
        "recommendations": []
    }
    
    for model, data in results.items():
        if data.get("status") != "completed":
            continue
        
        rc = data.get("result_counts", {})
        total = rc.get("total", 0)
        passed = rc.get("passed", 0)
        failed = rc.get("failed", 0)
        
        accuracy = passed / total if total > 0 else 0
        
        # Parse usage for cost estimation
        usage = data.get("per_model_usage", [])
        total_tokens = sum(u.get("total_tokens", 0) for u in usage) if usage else 0
        
        # Per-criteria breakdown
        criteria_results = data.get("per_testing_criteria_results", [])
        
        analysis["models"][model] = {
            "accuracy": accuracy,
            "passed": passed,
            "failed": failed,
            "total": total,
            "total_tokens": total_tokens,
            "criteria_results": criteria_results,
            "report_url": data.get("report_url"),
        }
        
        if accuracy > analysis["best_accuracy"]:
            analysis["best_accuracy"] = accuracy
            analysis["best_overall"] = model
    
    # Generate recommendations
    if analysis["best_overall"]:
        analysis["recommendations"].append(
            f"Best overall accuracy: {analysis['best_overall']} ({analysis['best_accuracy']*100:.1f}%)"
        )
    
    # Find best cost-effective option (nano/mini with >90% accuracy)
    cost_effective = [(m, d) for m, d in analysis["models"].items() 
                      if ("nano" in m or "mini" in m) and d["accuracy"] >= 0.90]
    if cost_effective:
        best_ce = max(cost_effective, key=lambda x: x[1]["accuracy"])
        analysis["recommendations"].append(
            f"Best cost-effective: {best_ce[0]} ({best_ce[1]['accuracy']*100:.1f}%)"
        )
    
    return analysis


def generate_markdown_report(analysis: dict) -> str:
    """Generate markdown report from analysis."""
    lines = [
        "# TrafficEye MMR Comparison Eval Results",
        "",
        "## Summary",
        "",
        f"**Best Overall:** {analysis['best_overall']} ({analysis['best_accuracy']*100:.1f}% accuracy)",
        "",
        "## Model Comparison",
        "",
        "| Model | Accuracy | Passed | Failed | Total | Tokens |",
        "|-------|----------|--------|--------|-------|--------|",
    ]
    
    # Sort by accuracy descending
    sorted_models = sorted(
        analysis["models"].items(),
        key=lambda x: x[1]["accuracy"],
        reverse=True
    )
    
    for model, data in sorted_models:
        acc = f"{data['accuracy']*100:.1f}%"
        lines.append(
            f"| {model} | {acc} | {data['passed']} | {data['failed']} | {data['total']} | {data['total_tokens']} |"
        )
    
    lines.extend([
        "",
        "## Recommendations",
        "",
    ])
    
    for rec in analysis["recommendations"]:
        lines.append(f"- {rec}")
    
    lines.extend([
        "",
        "## Per-Model Details",
        "",
    ])
    
    for model, data in sorted_models:
        lines.append(f"### {model}")
        lines.append("")
        if data.get("report_url"):
            lines.append(f"[View detailed report]({data['report_url']})")
        lines.append("")
        
        if data.get("criteria_results"):
            lines.append("**Per-Criteria Results:**")
            for cr in data["criteria_results"]:
                name = cr.get("testing_criteria", "Unknown")
                passed = cr.get("passed", 0)
                failed = cr.get("failed", 0)
                lines.append(f"- {name}: {passed} passed, {failed} failed")
            lines.append("")
    
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Analyze eval results")
    parser.add_argument("--output", choices=["json", "report", "both"], default="both",
                        help="Output format")
    args = parser.parse_args()
    
    print("Loading results...")
    results = load_results()
    
    print("Analyzing...")
    analysis = analyze_results(results)
    
    # Print summary
    print("\n" + "=" * 60)
    print("ANALYSIS SUMMARY")
    print("=" * 60)
    
    if analysis["best_overall"]:
        print(f"\nBest model: {analysis['best_overall']} ({analysis['best_accuracy']*100:.1f}%)")
    
    print("\nAll models:")
    for model, data in sorted(analysis["models"].items(), 
                               key=lambda x: x[1]["accuracy"], reverse=True):
        print(f"  {model}: {data['accuracy']*100:.1f}% ({data['passed']}/{data['total']})")
    
    print("\nRecommendations:")
    for rec in analysis["recommendations"]:
        print(f"  - {rec}")
    
    # Save outputs
    results_dir = Path(__file__).parent / "results"
    
    if args.output in ["json", "both"]:
        json_path = results_dir / "analysis.json"
        with open(json_path, "w") as f:
            json.dump(analysis, f, indent=2)
        print(f"\nJSON saved to: {json_path}")
    
    if args.output in ["report", "both"]:
        report = generate_markdown_report(analysis)
        report_path = results_dir / "comparison_report.md"
        with open(report_path, "w") as f:
            f.write(report)
        print(f"Report saved to: {report_path}")


if __name__ == "__main__":
    main()
