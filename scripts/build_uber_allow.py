#!/usr/bin/env python3
"""Scrape Uber eligible-vehicles page and produce uber_eligible.json.

The HTML contains each make as a collapsible list (<li><div><b>MAKE</b> ...).
We fetch the page (requires an Accept header), extract bold tags inside the
#vehicles section, deduplicate, sort, and write datasets/uber_eligible.json.

Run:
    python scripts/build_uber_allow.py --city boston
"""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "datasets" / "uber_eligible.json"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36",
    "Accept-Language": "en-US,en;q=0.9",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
}


def fetch(city: str) -> str:
    url = f"https://www.uber.com/global/en/eligible-vehicles/?city={city}"
    r = requests.get(url, headers=HEADERS, timeout=20)
    if r.status_code != 200:
        sys.exit(f"Failed to fetch {url}: {r.status_code}")
    return r.text


def parse_makes(html: str) -> list[str]:
    # crude regex to extract text inside <b>..</b> tags within vehicles section.
    section_match = re.search(r"<section[^>]+id=\"vehicles\"[\s\S]*?</section>", html, re.I)
    if section_match:
        html = section_match.group(0)
    texts = re.findall(r"<b[^>]*>(.*?)</b>", html, re.I | re.S)
    makes = set()
    for t in texts:
        txt = re.sub(r"<[^>]+>", "", t).strip()  # remove nested tags
        if txt and len(txt) > 2 and not re.search(r"\d{4}", txt):
            makes.add(txt)
    return sorted(makes)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--city", default="boston", help="city param for Uber URL")
    args = parser.parse_args()

    html = fetch(args.city)
    makes = parse_makes(html)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT, "w") as f:
        json.dump(makes, f, indent=2)
    print(f"Wrote {len(makes)} makes to {OUTPUT}")


if __name__ == "__main__":
    main()
