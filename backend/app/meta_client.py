"""The ONLY place that calls Meta's Model API.

Endpoints and formats follow the official docs at https://dev.meta.ai/docs
(checked Nov 2 2026):
  - Chat Completions  POST /chat/completions   (muse-spark-1.3, text + image)
  - Transcribe        POST /asr/transcribe     (muse-voice-transcribe-1.0, WAV only)
  - Responses         POST /responses          (sam-3.1, streamed text records)

The key is read from backend/.env (META_API_KEY) and never logged.
"""

from __future__ import annotations

import base64
import json
import os
import re
from dataclasses import dataclass

import httpx

BASE_URL = os.getenv("META_BASE_URL", "https://api.meta.ai/v1")
SPARK_MODEL = "muse-spark-1.3"
TRANSCRIBE_MODEL = "muse-voice-transcribe-1.0"
SAM_MODEL = "sam-3.1"

# muse-spark-1.3 always reasons, and max_tokens counts reasoning + answer
# together. Without a low effort and enough headroom the answer comes back
# empty (content=None), so both are set on every call.
DEFAULT_EFFORT = "low"
DEFAULT_MAX_TOKENS = 2000

TIMEOUT = httpx.Timeout(120.0, connect=15.0)


class MetaAPIError(RuntimeError):
    """Meta API failed. The message is short and safe to show (no key, no body dump)."""


def _key() -> str:
    key = os.getenv("META_API_KEY", "").strip()
    if not key:
        raise MetaAPIError("META_API_KEY is not set in backend/.env")
    return key


def _headers(**extra: str) -> dict:
    return {"Authorization": f"Bearer {_key()}", **extra}


def _raise_for(resp: httpx.Response, what: str) -> None:
    if resp.status_code < 400:
        return
    try:
        msg = resp.json().get("error", {}).get("message", "")
    except Exception:
        msg = ""
    raise MetaAPIError(f"{what} failed: HTTP {resp.status_code} {msg[:200]}".strip())


def data_url(image_bytes: bytes, mime: str = "image/jpeg") -> str:
    return f"data:{mime};base64,{base64.b64encode(image_bytes).decode()}"


# ---------------------------------------------------------------- Muse Spark

def chat(
    messages: list[dict],
    *,
    effort: str = DEFAULT_EFFORT,
    max_tokens: int = DEFAULT_MAX_TOKENS,
) -> str:
    """One Chat Completions call. Returns the answer text (never None)."""
    body = {
        "model": SPARK_MODEL,
        "messages": messages,
        "reasoning_effort": effort,
        "max_tokens": max_tokens,
    }
    try:
        resp = httpx.post(f"{BASE_URL}/chat/completions", headers=_headers(), json=body, timeout=TIMEOUT)
    except httpx.HTTPError as e:
        raise MetaAPIError(f"Muse Spark unreachable: {type(e).__name__}") from e
    _raise_for(resp, "Muse Spark")
    choice = resp.json()["choices"][0]
    text = choice["message"].get("content")
    if not text:
        raise MetaAPIError(f"Muse Spark returned no answer (finish_reason={choice.get('finish_reason')})")
    return text


def ask_text(prompt: str, *, system: str | None = None, **kw) -> str:
    messages = [{"role": "system", "content": system}] if system else []
    messages.append({"role": "user", "content": prompt})
    return chat(messages, **kw)


def ask_image(prompt: str, image_bytes: bytes, mime: str = "image/jpeg", **kw) -> str:
    """Muse Spark reads an image. Images are only allowed in user messages."""
    content = [
        {"type": "text", "text": prompt},
        {"type": "image_url", "image_url": {"url": data_url(image_bytes, mime)}},
    ]
    return chat([{"role": "user", "content": content}], **kw)


# ---------------------------------------------------------- Voice Transcribe

@dataclass
class Transcript:
    text: str
    duration_ms: int
    session_id: str


def transcribe(wav_bytes: bytes, language_bias: list[str] | None = None,
               keywords: list[str] | None = None) -> Transcript:
    """WAV only: mono integer PCM at 16 kHz or 24 kHz, max 10 minutes / 32 MB."""
    request: dict = {"model": TRANSCRIBE_MODEL, "audioEncoding": "WAV", "mode": "PUSH_TO_TALK"}
    if language_bias:
        request["languageBias"] = language_bias
    if keywords:
        request["keywords"] = keywords[:100]
    files = {
        "request": (None, json.dumps(request), "application/json"),
        "audio": ("audio.wav", wav_bytes, "audio/wav"),
    }
    try:
        resp = httpx.post(
            f"{BASE_URL}/asr/transcribe",
            headers=_headers(Accept="application/json"),
            files=files,
            timeout=TIMEOUT,
        )
    except httpx.HTTPError as e:
        raise MetaAPIError(f"Voice Transcribe unreachable: {type(e).__name__}") from e
    _raise_for(resp, "Voice Transcribe")
    data = resp.json()
    return Transcript(
        text=data.get("transcript", ""),
        duration_ms=int(data.get("audioDurationMs", 0)),
        session_id=data.get("sessionId", ""),
    )


# ------------------------------------------------------------------- SAM 3.1

@dataclass
class Box:
    x1: int
    y1: int
    x2: int
    y2: int
    w: int
    h: int
    confidence: float | None


_BOX_RE = re.compile(r"<\|box;([^|]*)\|>")


def parse_boxes(output_text: str) -> list[Box]:
    """Pull every `<|box;x1=..;y1=..;x2=..;y2=..;w=..;h=..[;c=..]|>` record.

    Masks are left in the raw text; Phase 8 decodes them for the overlay.
    """
    boxes = []
    for m in _BOX_RE.finditer(output_text):
        f = dict(kv.split("=", 1) for kv in m.group(1).split(";") if "=" in kv)
        boxes.append(Box(
            int(f["x1"]), int(f["y1"]), int(f["x2"]), int(f["y2"]),
            int(f["w"]), int(f["h"]),
            float(f["c"]) if "c" in f else None,
        ))
    return boxes


def segment(image_bytes: bytes, concept: str, mime: str = "image/jpeg") -> str:
    """SAM 3.1 with a text prompt (one noun phrase). Returns the joined output text.

    Streamed per the docs: results arrive as `response.output_text.delta`
    events and the stream ends with `response.completed`. No match = "".
    """
    body = {
        "model": SAM_MODEL,
        "input": [{
            "type": "message",
            "role": "user",
            "content": [
                {"type": "input_text", "text": concept},
                {"type": "input_image", "image_url": data_url(image_bytes, mime)},
            ],
        }],
        "stream": True,
        "metadata": {"include_confidence": "true"},
    }
    chunks: list[str] = []
    try:
        with httpx.stream(
            "POST", f"{BASE_URL}/responses",
            headers=_headers(Accept="text/event-stream"),
            json=body, timeout=TIMEOUT,
        ) as resp:
            if resp.status_code >= 400:
                resp.read()
                _raise_for(resp, "SAM 3.1")
            for line in resp.iter_lines():
                if not line.startswith("data:"):
                    continue
                payload = line[5:].strip()
                if not payload or payload == "[DONE]":
                    continue
                event = json.loads(payload)
                kind = event.get("type")
                if kind == "response.output_text.delta":
                    chunks.append(event.get("delta", ""))
                elif kind in ("error", "response.failed"):
                    raise MetaAPIError("SAM 3.1 failed during streaming")
    except httpx.HTTPError as e:
        raise MetaAPIError(f"SAM 3.1 unreachable: {type(e).__name__}") from e
    return "".join(chunks)
