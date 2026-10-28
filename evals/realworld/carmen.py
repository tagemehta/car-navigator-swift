"""Carmen Cloud vehicle MMR client with an on-disk cache (one call per image, ever).

Returns the MMR in the same shape as TrafficEye's ({key: {"value", "score"}}, scores 0-1) so the
`carmen:` pipeline can reuse the TrafficEye comparison step unchanged. Carmen reports color as RGB;
the response usually includes `colorName`; otherwise `color_name()` maps it to a TrafficEye-style name (WHITE, SILVER, ...) and the raw RGB is kept.
"""

from __future__ import annotations

import colorsys
import json
import threading
import time

import requests

from common import CACHE_DIR, read_secret

# North America region; plates are not needed, so only MMR is requested.
REGION = "nam"
ENDPOINT = f"https://api.carmencloud.com/vehicle/{REGION}"
CACHE = CACHE_DIR / "carmen"
_lock = threading.Lock()


def color_name(r: int, g: int, b: int) -> str:
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if v < 0.2:
        return "BLACK"
    if s < 0.18:
        return "WHITE" if v > 0.85 else "SILVER" if v > 0.6 else "GRAY" if v > 0.3 else "BLACK"
    deg = h * 360
    if s < 0.45 and 20 <= deg < 60:
        return "BEIGE" if v > 0.6 else "BROWN"
    for limit, name in ((15, "RED"), (40, "ORANGE"), (70, "YELLOW"), (165, "GREEN"),
                        (255, "BLUE"), (290, "PURPLE"), (340, "PINK"), (360, "RED")):
        if deg < limit:
            if name == "ORANGE" and v < 0.6:
                return "BROWN"
            return name
    return "RED"


def to_mmr(raw: dict | None) -> dict | None:
    if not raw or not raw.get("found"):
        return None
    pct = lambda k: (raw.get(k) or 0) / 100  # noqa: E731
    mmr = {}
    if raw.get("make"):
        mmr["make"] = {"value": raw["make"], "score": pct("makeConfidence")}
    if raw.get("model"):
        mmr["model"] = {"value": raw["model"], "score": pct("modelConfidence")}
    if c := raw.get("color"):
        name = raw.get("colorName") or color_name(c["r"], c["g"], c["b"])
        mmr["color"] = {"value": name, "score": pct("colorConfidence")}
    if raw.get("heading"):
        mmr["view"] = {"value": raw["heading"], "score": pct("headingConfidence")}
    return mmr or None


def cached(image_id: str) -> dict | None:
    path = CACHE / f"{image_id}.json"
    return json.loads(path.read_text()) if path.exists() else None


def recognize(image_id: str, jpeg: bytes) -> dict:
    """Return {"mmr": dict|None, "raw": dict|None, "latency_s", "error"}, cached by image_id."""
    if hit := cached(image_id):
        return hit
    start = time.perf_counter()
    try:
        resp = requests.post(
            ENDPOINT,
            headers={"Accept": "application/json", "X-Api-Key": read_secret("CARMEN_API_KEY")},
            data={"service": "mmr", "maxreads": "1"},
            files={"image": ("image.jpg", jpeg, "image/jpeg")},
            timeout=30,
        )
        latency = time.perf_counter() - start
        if resp.status_code >= 400:
            # Never echo headers; the body is the API's own error message.
            raise RuntimeError(f"HTTP {resp.status_code}: {resp.text[:200]}")
        vehicles = ((resp.json().get("data") or {}).get("vehicles")) or []
        raw = vehicles[0].get("mmr") if vehicles else None
        result = {"mmr": to_mmr(raw), "raw": raw, "latency_s": latency, "error": None}
    except Exception as e:  # noqa: BLE001 - errors are not cached
        return {"mmr": None, "raw": None, "latency_s": time.perf_counter() - start,
                "error": f"{type(e).__name__}: {e}"[:300]}
    with _lock:
        CACHE.mkdir(parents=True, exist_ok=True)
        (CACHE / f"{image_id}.json").write_text(json.dumps(result))
    return result
