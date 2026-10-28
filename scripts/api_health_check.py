#!/usr/bin/env python3
"""
API health check for TrafficEye and OpenAI.

Intended to run from cron (or launchd) to verify that API keys and endpoints
are working. The script exits with code 0 only when both APIs return valid
responses.

Key resolution order (first match wins):
  1. Environment variables: OPENAI_API, TRAFFICEYE_API_KEY
  2. scripts/.env
  3. thing-finder/Secrets.xcconfig
"""

import base64
import json
import os
import re
import sys
import subprocess
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ENV_FILE = REPO_ROOT / "scripts" / ".env"
SECRETS_FILE = REPO_ROOT / "thing-finder" / "Secrets.xcconfig"

# Tiny 100x100 red JPEG encoded as base64. Used as the TrafficEye test payload
# so the script has no external dependencies.
TEST_JPEG_B64 = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAUDBAQEAwUEBAQFBQUGBwwIBwcHBw8LCwkMEQ8SEhEPERETFhwXExQaFRERGCEYGh0dHx8fExciJCIeJBweHx7/2wBDAQUFBQcGBw4ICA4eFBEUHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh7/wAARCABkAGQDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDyyiiivzo/ssKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooA//2Q=="


def log(message: str) -> None:
    timestamp = datetime.now(timezone.utc).isoformat()
    print(f"{timestamp} {message}", flush=True)


def notify(title: str, message: str) -> None:
    """Send a Slack notification, falling back to a native macOS notification."""
    slack_webhook_url = resolve_api_key("SLACK_WEBHOOK_URL")
    if slack_webhook_url:
        try:
            payload = json.dumps({
                "text": f"*{title}*\n{message}",
                "username": "thing-finder-health-check",
            }).encode("utf-8")
            request = urllib.request.Request(
                slack_webhook_url,
                data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            with urllib.request.urlopen(request, timeout=15) as response:
                # Slack returns "ok" on success.
                _ = response.read()
            return
        except Exception:  # noqa: BLE001, S110
            # Fall through to macOS notification if Slack fails.
            pass

    # Fallback: native macOS notification.
    try:
        subprocess.run(
            [
                "/usr/bin/osascript",
                "-e",
                f'display notification "{message}" with title "{title}" sound name "Glass"',
            ],
            check=False,
            capture_output=True,
        )
    except Exception:  # noqa: BLE001, S110
        pass


def _parse_env_text(text: str) -> dict[str, str]:
    env: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith("//"):
            continue
        # Support KEY=VALUE, KEY = VALUE, and KEY = "VALUE"
        match = re.match(r"([A-Za-z0-9_]+)\s*=\s*(.+)", line)
        if match:
            key = match.group(1).strip()
            value = match.group(2).strip().strip('"').strip("'")
            env[key] = value
    return env


def _load_env_file(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    return _parse_env_text(path.read_text(encoding="utf-8"))


def _load_secrets_xcconfig(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    return _parse_env_text(path.read_text(encoding="utf-8"))


def resolve_api_key(*names: str) -> str | None:
    """Return the first non-empty value found across env, .env, and Secrets.xcconfig."""
    sources = [
        os.environ,
        _load_env_file(ENV_FILE),
        _load_secrets_xcconfig(SECRETS_FILE),
    ]
    for source in sources:
        for name in names:
            value = source.get(name)
            if value:
                return value
    return None


def test_openai(api_key: str) -> bool:
    endpoint = "https://api.openai.com/v1/chat/completions"
    payload = {
        "model": "gpt-4.1-mini",
        "messages": [{"role": "user", "content": "Say OK"}],
        "max_tokens": 5,
    }
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = json.loads(response.read())
            if data.get("choices"):
                log(f"OpenAI OK: model={data.get('model', 'unknown')}")
                return True
            log(f"OpenAI FAIL: unexpected response shape: {json.dumps(data)}")
            return False
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="ignore")
        log(f"OpenAI FAIL: HTTP {exc.code}: {body}")
        return False
    except Exception as exc:  # noqa: BLE001
        log(f"OpenAI FAIL: {exc}")
        return False


def trafficeye_response_ok(data: object) -> bool:
    """Accept only TrafficEye's success envelope: {"data": {"combinations": [...]}}.

    Mirrors what TrafficEyeVerifier decodes. The test image is blank, so an empty
    `combinations` list is a healthy response; this checks API availability, not detection.
    """
    payload = data.get("data") if isinstance(data, dict) else None
    combos = payload.get("combinations", []) if isinstance(payload, dict) else None
    if not isinstance(payload, dict) or not isinstance(combos, list):
        log(f"TrafficEye FAIL: unexpected response shape: {json.dumps(data)[:500]}")
        return False
    log(f"TrafficEye OK: success envelope with {len(combos)} combination(s)")
    return True


def test_trafficeye(api_key: str) -> bool:
    endpoint = "https://trafficeye.ai/recognition"
    image_bytes = base64.b64decode(TEST_JPEG_B64)
    boundary = "----HealthCheckBoundary7MA4YWxkTrZu0gW"

    body_parts = [
        f"--{boundary}\r\n".encode("utf-8"),
        b'Content-Disposition: form-data; name="request"\r\n\r\n',
        json.dumps({"saveImage": False, "tasks": ["DETECTION", "OCR", "MMR"]}).encode(
            "utf-8"
        ),
        f"\r\n--{boundary}\r\n".encode("utf-8"),
        b'Content-Disposition: form-data; name="file"; filename="test.jpg"\r\n',
        b"Content-Type: image/jpeg\r\n\r\n",
        image_bytes,
        f"\r\n--{boundary}--\r\n".encode("utf-8"),
    ]
    body = b"".join(body_parts)

    request = urllib.request.Request(
        endpoint,
        data=body,
        headers={
            "apiKey": api_key,
            "Content-Type": f"multipart/form-data; boundary={boundary}",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            data = json.loads(response.read())
        return trafficeye_response_ok(data)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="ignore")
        log(f"TrafficEye FAIL: HTTP {exc.code}: {body}")
        return False
    except Exception as exc:  # noqa: BLE001
        log(f"TrafficEye FAIL: {exc}")
        return False


def main() -> int:
    openai_key = resolve_api_key("OPENAI_API")
    trafficeye_key = resolve_api_key("TRAFFICEYE_API_KEY")

    failures: list[str] = []
    if not openai_key:
        log(
            "OpenAI FAIL: OPENAI_API key not found in environment, scripts/.env, or Secrets.xcconfig"
        )
        failures.append("openai_key")
    if not trafficeye_key:
        log(
            "TrafficEye FAIL: TRAFFICEYE_API_KEY key not found in environment, scripts/.env, or Secrets.xcconfig"
        )
        failures.append("trafficeye_key")

    if failures:
        notify(
            "API Health Check Failed",
            "Could not find OpenAI or TrafficEye API keys. Check Secrets.xcconfig or scripts/.env.",
        )
        return 1

    results = [
        test_openai(openai_key),
        test_trafficeye(trafficeye_key),
    ]

    if all(results):
        log("All API health checks passed")
        return 0

    log("One or more API health checks failed")
    notify(
        "API Health Check Failed",
        "TrafficEye or OpenAI returned an error. See scripts/api-health-check.log for details.",
    )
    return 1


if __name__ == "__main__":
    sys.exit(main())
