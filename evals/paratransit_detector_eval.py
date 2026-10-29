"""Eval for ParatransitDetector: does the LLM tell transit/paratransit vehicles from rideshare cars?

Mirrors thing-finder/Utilities/ParatransitDetector.swift (same model, system prompt, tool schema).

    python3 evals/paratransit_detector_eval.py --secrets /path/to/Secrets.xcconfig
"""

from __future__ import annotations

import argparse
import json
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "realworld"))
import common  # noqa: E402

MODEL = "gpt-6-luna"

TOOL = {
    "type": "function",
    "function": {
        "name": "classify_vehicle_request",
        "description": "Classify what kind of vehicle the user is waiting for.",
        "strict": True,
        "parameters": {
            "type": "object",
            "properties": {
                "category": {
                    "type": "string",
                    "description": (
                        "make_model_car: a private car (rideshare such as Uber or Lyft) identified by make, model, color or plate. "
                        "service_vehicle: any vehicle identified by something other than its make and model: a taxi, bus, "
                        "paratransit van, shuttle or similar fleet vehicle, recognized by its color scheme, route number, "
                        "agency, logo, service name or other markings."
                    ),
                    "enum": ["make_model_car", "service_vehicle"],
                }
            },
            "required": ["category"],
            "additionalProperties": False,
        },
    },
}

SERVICE = [
    "accesslink van",
    "white accesslink van",
    "Access-A-Ride van",
    "MTA Access-A-Ride",
    "paratransit van",
    "white paratransit van with wheelchair lift",
    "my paratransit ride",
    "Metro Mobility bus",
    "Metro Access van",
    "MetroLift van",
    "DART paratransit",
    "TheRide paratransit",
    "RIDE paratransit van",
    "Para-transit minibus",
    "ADA paratransit vehicle",
    "wheelchair accessible van from the city",
    "Route 42 bus",
    "blue MTA bus",
    "SEPTA bus",
    "the 15 bus",
    "M60 bus",
    "Muni 38 Geary",
    "red CTA bus number 22",
    "white shuttle bus with a green stripe",
    "airport shuttle",
    "hotel shuttle van",
    "Dial-a-ride van",
    "medical transport van with lift",
    "Sacramento Regional Transit bus",
    "yellow taxi",
    "NYC yellow cab",
    "Checker cab",
    "Yellow Cab",
    "yellow school bus",
]

MAKE_MODEL = [
    "white Toyota Camry",
    "silver Honda Accord ABC1234",
    "black Tesla Model 3",
    "blue Hyundai Elantra",
    "gray Nissan Altima with Lyft sticker",
    "red Ford Fusion",
    "white Chevy Malibu",
    "black Toyota Prius",
    "silver Kia Soul",
    "dark blue Honda Civic 7XYZ123",
    "white Toyota Sienna minivan",
    "black Chrysler Pacifica",
    "silver Honda Odyssey",
    "white Ford Transit",
    "gray Dodge Grand Caravan",
    "black Chevy Suburban",
    "white Tesla Model Y",
    "green Subaru Outback",
    "tan Toyota RAV4",
    "black Lincoln Navigator",
    "white Mercedes Sprinter van Uber XL",
    "silver Toyota Highlander",
    "black Uber Honda CR-V",
    "red Mazda 3",
    "gray Volkswagen Jetta",
    "white Nissan Rogue with an Uber sticker",
    "blue Chevy Bolt",
]


def make_client(plist: Path | None = None):
    """Go through the CurbToCar proxy like the app does; fall back to the direct key if not configured.

    Proxy settings come from the environment, Secrets.xcconfig, or a built app's Info.plist (--plist).
    """
    import plistlib

    try:
        if plist:
            info = plistlib.loads(plist.read_bytes())
            base, token = info["PROXY_BASE_URL"], info["PROXY_APP_TOKEN"]
        else:
            base, token = common.read_secret("PROXY_BASE_URL"), common.read_secret("PROXY_APP_TOKEN")
        base = base.replace("$()", "").rstrip("/")
    except (KeyError, FileNotFoundError):
        return common.client()
    from openai import OpenAI

    return OpenAI(
        api_key="unused",
        base_url=f"{base}/v1",
        default_headers={"X-App-Token": token, "X-Device-Id": "eval-paratransit-detector"},
        max_retries=3,
        timeout=60,
    )


def classify(client, description: str) -> str:
    resp = client.chat.completions.create(
        model=MODEL,
        messages=[
            {"role": "system", "content": "Classify the vehicle the user is waiting for from their description."},
            {"role": "user", "content": description},
        ],
        tools=[TOOL],
        tool_choice="required",
        max_completion_tokens=50,
        reasoning_effort="none",
    )
    args = resp.choices[0].message.tool_calls[0].function.arguments
    return json.loads(args)["category"]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--secrets", type=Path, help="Path to Secrets.xcconfig (defaults to the repo's)")
    ap.add_argument("--plist", type=Path, help="Built app Info.plist containing PROXY_BASE_URL/PROXY_APP_TOKEN")
    ap.add_argument("--max-requests", type=int, default=70)
    args = ap.parse_args()
    if args.secrets:
        common.SECRETS = args.secrets

    cases = [(d, "service_vehicle") for d in SERVICE] + [(d, "make_model_car") for d in MAKE_MODEL]
    if len(cases) > args.max_requests:
        sys.exit(f"{len(cases)} requests planned, over --max-requests {args.max_requests}")
    print(f"{len(cases)} requests to {MODEL}")

    client = make_client(args.plist)
    with ThreadPoolExecutor(max_workers=4) as pool:
        got = list(pool.map(lambda c: classify(client, c[0]), cases))

    for label in ("service_vehicle", "make_model_car"):
        rows = [(c, g) for c, g in zip(cases, got) if c[1] == label]
        ok = sum(g == label for _, g in rows)
        print(f"\n{label}: {ok}/{len(rows)} correct")
        for (desc, _), g in rows:
            if g != label:
                print(f"  WRONG  {desc!r} -> {g}")


if __name__ == "__main__":
    main()
