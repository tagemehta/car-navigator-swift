#!/usr/bin/env python3
"""
OpenAI Evals API configuration for TrafficEye MMR to user description comparison.

Creates an eval that tests model ability to:
1. Correctly classify match/mismatch/maybe
2. Provide reasonable probability estimates
3. Handle edge cases (color variations, abbreviations, etc.)
"""

import os
from pathlib import Path
from openai import OpenAI

_client = None


def _load_api_key_from_xcconfig() -> str | None:
    """Load OPENAI_API from Secrets.xcconfig if not in environment."""
    xcconfig_path = Path(__file__).parent.parent / "thing-finder" / "Secrets.xcconfig"
    if xcconfig_path.exists():
        with open(xcconfig_path) as f:
            for line in f:
                if line.startswith("OPENAI_API"):
                    parts = line.split("=", 1)
                    if len(parts) == 2:
                        return parts[1].strip()
    return None


def get_client():
    """Lazy initialization of OpenAI client."""
    global _client
    if _client is None:
        api_key = os.environ.get("OPENAI_API_KEY") or _load_api_key_from_xcconfig()
        if not api_key:
            raise ValueError(
                "No API key found. Set OPENAI_API_KEY or add to Secrets.xcconfig"
            )
        _client = OpenAI(api_key=api_key)
    return _client


# Current production prompt from TrafficEyeVerifier.swift
SYSTEM_PROMPT = """You are a vehicle verification expert. You are given the output of an ML vehicle recognition API (including make, model, color, and confidence scores for each), and a user's natural language description of their vehicle. The ML output may be imperfect.
Your job is to estimate the probability (0-1) that the ML prediction refers to the same car as described by the user, **and** provide a semantic_reason:
- "match" if confident they are the same car.
- "mismatch" if confident they are different.
- "maybe" when uncertain or info is missing.
You are necessary because there are differences in the technical api output and the plain language user input (like dashes, abbreviations, slight color differences) and we still need a robust way to match the descriptions.
Consider:
- If the make and color are correct and the model is similar (and low-confidence), a match is likely.
- If the api provides more information than the user, (e.g. API - Red honda civic User - Honda civic or Red civic) consider them to be equal
- If the make is correct but the model is very different (e.g. Accord vs CR-V), it's likely not a match.
- If a license plate is part of the user prompt but none is provided by the api, treat it as a non-factor
The API only outputs colors as "BLUE", "BROWN", "YELLOW", "GRAY", "GREEN", "PURPLE", "RED", "WHITE", "BLACK", "ORANGE".
Therefore, treat colors that are roughly equivalent (silver vs gray) as equal
- Take the confidence scores into account for each attribute.
Output your reasoning and call the submit_match_decision function with your probability and justification."""

USER_PROMPT_TEMPLATE = """ML API prediction (JSON):
{{ item.mmr_json }}

User's description: '{{ item.user_description }}'

What is the probability (0-1) that the ML prediction is referring to the same car as the user described? Justify briefly."""

# Tool schema for structured output
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


def create_eval(name: str = "TrafficEye MMR Comparison") -> dict:
    """Create the eval configuration via OpenAI API."""

    eval_config = get_client().evals.create(
        name=name,
        data_source_config={
            "type": "custom",
            "item_schema": {
                "type": "object",
                "properties": {
                    "mmr_json": {"type": "string"},
                    "user_description": {"type": "string"},
                    "expected_decision": {"type": "string"},
                    "expected_probability": {"type": "number"},
                    "info_quality": {"type": "string"},
                    "test_case_type": {"type": "string"},
                },
                "required": [
                    "mmr_json",
                    "user_description",
                    "expected_decision",
                    "expected_probability",
                ],
            },
            "include_sample_schema": True,
        },
        testing_criteria=[
            # Primary: Extract semantic_reason from JSON and check exact match
            {
                "type": "python",
                "name": "Semantic Reason Accuracy",
                "code": "import json; output = json.loads(sample['output_text']); 'PASS' if output.get('semantic_reason') == item['expected_decision'] else 'FAIL'",
                "passing_labels": ["PASS"],
            },
            # Secondary: Label model evaluation for nuanced cases
            {
                "type": "label_model",
                "name": "Decision Quality",
                "model": "gpt-4.1",
                "input": [
                    {
                        "role": "system",
                        "content": """You are evaluating a vehicle matching decision. Given the MMR API output, user description, expected decision, and model output, respond with exactly one word: PASS or FAIL.
PASS if the semantic_reason matches expected OR is reasonably close given the inputs.
FAIL if the decision is clearly wrong.""",
                    },
                    {
                        "role": "user",
                        "content": """MMR: {{ item.mmr_json }}
User description: {{ item.user_description }}
Expected: {{ item.expected_decision }}
Model output: {{ sample.output_text }}""",
                    },
                ],
                "labels": ["PASS", "FAIL"],
                "passing_labels": ["PASS"],
            },
        ],
    )

    return eval_config


def upload_test_data(filepath: str) -> str:
    """Upload test data file and return file ID."""
    with open(filepath, "rb") as f:
        file_obj = get_client().files.create(file=f, purpose="evals")
    return file_obj.id


def get_eval_by_name(name: str) -> dict | None:
    """Find existing eval by name."""
    evals = get_client().evals.list()
    for e in evals.data:
        if e.name == name:
            return e
    return None


if __name__ == "__main__":
    # Check for existing eval or create new one
    eval_name = "TrafficEye MMR Comparison"
    existing = get_eval_by_name(eval_name)

    if existing:
        print(f"Found existing eval: {existing.id}")
        print(f"  Name: {existing.name}")
        print(f"  Created: {existing.created_at}")
    else:
        print("Creating new eval...")
        eval_obj = create_eval(eval_name)
        print(f"Created eval: {eval_obj.id}")
        print(f"  Name: {eval_obj.name}")
