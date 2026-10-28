"""Shared config for the real-image verifier eval: paths, secrets, pricing, LLM calls."""

from __future__ import annotations

import base64
import io
import json
import os
import time
from dataclasses import dataclass
from pathlib import Path

from openai import OpenAI
from PIL import Image

REPO_ROOT = Path(__file__).resolve().parents[2]
EVAL_ROOT = REPO_ROOT / "evals"
CACHE_DIR = EVAL_ROOT / "cache"
DATA_DIR = EVAL_ROOT / "data"
RESULTS_DIR = EVAL_ROOT / "results" / "realworld"
DATASETS = REPO_ROOT / "datasets"
SECRETS = REPO_ROOT / "thing-finder" / "Secrets.xcconfig"

# Matches the longest side of the crops the app sends; keeps image tokens realistic.
MAX_IMAGE_SIDE = 640
JPEG_QUALITY = 85

# USD per 1M tokens (input, output) from developers.openai.com/api/docs/pricing, 2026-10-16.
PRICES = {
    "gpt-4.1-mini": (0.40, 1.60),
    "gpt-4.1": (2.00, 8.00),
    "gpt-6-luna": (0.10, 0.50),
    "gpt-5.6-luna": (0.20, 1.20),
    "gpt-5.6-terra": (2.00, 12.00),
    "gpt-5.4-nano": (0.20, 1.25),
    "gpt-5.4-mini": (0.75, 4.50),
    "gpt-6-sol": (2.00, 10.00),
    "gpt-6.1-sol": (2.00, 10.00),
}
NON_REASONING = {"gpt-4.1-mini", "gpt-4.1"}


def read_secret(name: str) -> str:
    if os.environ.get(name):
        return os.environ[name]
    for line in SECRETS.read_text().splitlines():
        key, sep, value = line.partition("=")
        if sep and key.strip() == name:
            return value.strip()
    raise KeyError(f"{name} not found in environment or {SECRETS}")


_client: OpenAI | None = None


def client() -> OpenAI:
    global _client
    if _client is None:
        _client = OpenAI(api_key=read_secret("OPENAI_API"), max_retries=3, timeout=60)
    return _client


def load_jpeg(path: Path, bbox: list[int] | None = None) -> bytes:
    """Load an image, optionally crop to a padded bbox, downscale, and re-encode as JPEG."""
    img = Image.open(path).convert("RGB")
    if bbox:
        x1, y1, x2, y2 = bbox
        pad_x, pad_y = int((x2 - x1) * 0.08), int((y2 - y1) * 0.08)
        img = img.crop(
            (max(0, x1 - pad_x), max(0, y1 - pad_y), min(img.width, x2 + pad_x), min(img.height, y2 + pad_y))
        )
    img.thumbnail((MAX_IMAGE_SIDE, MAX_IMAGE_SIDE))
    buf = io.BytesIO()
    img.save(buf, format="JPEG", quality=JPEG_QUALITY)
    return buf.getvalue()


def data_url(jpeg: bytes) -> str:
    return "data:image/jpeg;base64," + base64.b64encode(jpeg).decode()


@dataclass(frozen=True)
class ModelConfig:
    """A model plus reasoning effort. `effort=None` means the param is omitted."""

    model: str
    effort: str | None = None

    @property
    def name(self) -> str:
        return self.model + (f"@{self.effort}" if self.effort else "")

    @staticmethod
    def parse(spec: str) -> "ModelConfig":
        model, _, effort = spec.partition("@")
        return ModelConfig(model, effort or None)


@dataclass
class LLMResult:
    args: dict | None
    latency_s: float
    input_tokens: int
    output_tokens: int
    cost_usd: float
    error: str | None = None


def call_structured(
    cfg: ModelConfig,
    messages: list[dict],
    fn_name: str,
    fn_description: str,
    schema: dict,
) -> LLMResult:
    """Call Chat Completions and return parsed arguments.

    Uses a function tool (as the Swift app does) when the model allows it on Chat
    Completions, i.e. non-reasoning models or effort=none. Otherwise falls back to
    strict json_schema output, since some reasoning models reject tools there.
    """
    use_tool = cfg.model in NON_REASONING or cfg.effort == "none"
    kwargs: dict = {"model": cfg.model, "messages": messages}
    if cfg.model in NON_REASONING:
        kwargs["temperature"] = 0
        kwargs["max_tokens"] = 300
    else:
        kwargs["max_completion_tokens"] = 300 if cfg.effort == "none" else 4000
        if cfg.effort:
            kwargs["reasoning_effort"] = cfg.effort
    if use_tool:
        kwargs["tools"] = [
            {
                "type": "function",
                "function": {"name": fn_name, "description": fn_description, "parameters": schema, "strict": True},
            }
        ]
        kwargs["tool_choice"] = {"type": "function", "function": {"name": fn_name}}
    else:
        kwargs["response_format"] = {
            "type": "json_schema",
            "json_schema": {"name": fn_name, "schema": schema, "strict": True},
        }

    start = time.perf_counter()
    try:
        resp = client().chat.completions.create(**kwargs)
    except Exception as e:  # noqa: BLE001 - recorded per case, never fatal
        return LLMResult(None, time.perf_counter() - start, 0, 0, 0.0, f"{type(e).__name__}: {e}"[:300])
    latency = time.perf_counter() - start

    usage = resp.usage
    in_tok, out_tok = usage.prompt_tokens, usage.completion_tokens
    price_in, price_out = PRICES.get(cfg.model, (0.0, 0.0))
    cost = (in_tok * price_in + out_tok * price_out) / 1e6

    msg = resp.choices[0].message
    raw = msg.tool_calls[0].function.arguments if use_tool and msg.tool_calls else msg.content
    try:
        args = json.loads(raw) if raw else None
        err = None if args else "empty response"
    except json.JSONDecodeError:
        args, err = None, f"unparseable: {raw[:200]}"
    return LLMResult(args, latency, in_tok, out_tok, cost, err)
