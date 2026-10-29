"""TrafficEye recognition client with an on-disk cache (one call per image, ever)."""

from __future__ import annotations

import json
import threading
import time

import requests

from common import CACHE_DIR, read_secret

ENDPOINT = "https://trafficeye.ai/recognition"
REQUEST_JSON = json.dumps({"saveImage": False, "tasks": ["DETECTION", "OCR", "MMR"]})
CACHE = CACHE_DIR / "trafficeye"
_lock = threading.Lock()


def cached(image_id: str) -> dict | None:
    path = CACHE / f"{image_id}.json"
    return json.loads(path.read_text()) if path.exists() else None


def recognize(image_id: str, jpeg: bytes) -> dict:
    """Return {"mmr": dict|None, "latency_s": float, "error": str|None}, cached by image_id."""
    if hit := cached(image_id):
        return hit
    start = time.perf_counter()
    try:
        resp = requests.post(
            ENDPOINT,
            headers={"apiKey": read_secret("TRAFFICEYE_API_KEY")},
            files={"request": (None, REQUEST_JSON), "file": ("image.jpg", jpeg, "image/jpeg")},
            timeout=30,
        )
        latency = time.perf_counter() - start
        resp.raise_for_status()
        body = resp.json()
        # Mirror TrafficEyeVerifier: first road user of the first combination.
        combos = (body.get("data") or {}).get("combinations") or []
        road_users = (combos[0].get("roadUsers") or []) if combos else []
        mmr = road_users[0].get("mmr") if road_users else None
        result = {"mmr": mmr, "latency_s": latency, "error": None}
    except Exception as e:  # noqa: BLE001 - network errors are not cached
        return {"mmr": None, "latency_s": time.perf_counter() - start, "error": f"{type(e).__name__}: {e}"[:300]}
    with _lock:
        CACHE.mkdir(parents=True, exist_ok=True)
        (CACHE / f"{image_id}.json").write_text(json.dumps(result))
    return result
