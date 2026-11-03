"""Phase 2 check: one real call to each of the 4 Meta capabilities.

Run from backend/:  .venv/bin/python -m scripts.phase2_check [--wav path.wav]

Test inputs are generated here (a drawn ledger page and drawn circles) so no
personal photos are sent. Without --wav a short tone is used, which proves the
endpoint works but has no words in it; pass a real 16 kHz mono WAV to see a
real transcript.
"""

from __future__ import annotations

import argparse
import io
import math
import struct
import wave

from dotenv import load_dotenv
from PIL import Image, ImageDraw, ImageFont

load_dotenv()

from app import meta_client as mc  # noqa: E402  (needs .env loaded first)


def tone_wav(seconds: float = 1.5, rate: int = 16000) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(
            struct.pack("<h", int(8000 * math.sin(2 * math.pi * 440 * i / rate)))
            for i in range(int(seconds * rate))
        ))
    return buf.getvalue()


def _font(size: int):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",):
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            pass
    return ImageFont.load_default()


def ledger_page_png() -> bytes:
    img = Image.new("RGB", (800, 420), "white")
    d = ImageDraw.Draw(img)
    f = _font(30)
    d.text((40, 30), "Demo Shop - Udhaar", fill="black", font=f)
    for i, row in enumerate(["Ramesh   450", "Sita     200 paid", "Maria    1,250"]):
        y = 110 + i * 90
        d.line((30, y + 55, 770, y + 55), fill="#99b", width=2)
        d.text((60, y), row, fill="#123", font=f)
    out = io.BytesIO()
    img.save(out, "PNG")
    return out.getvalue()


def circles_png(n: int = 5) -> bytes:
    img = Image.new("RGB", (800, 300), "#f4f1ea")
    d = ImageDraw.Draw(img)
    for i in range(n):
        x = 60 + i * 145
        d.ellipse((x, 90, x + 110, 200), fill="#e8711a", outline="#a34a08", width=4)
    out = io.BytesIO()
    img.save(out, "PNG")
    return out.getvalue()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--wav", help="real 16 kHz mono WAV to transcribe")
    args = ap.parse_args()

    print("1) Muse Spark (text)")
    print("   ->", mc.ask_text("In one short sentence: what is a shop credit ledger?"))

    print("2) Muse Spark (image)")
    print("   ->", mc.ask_image(
        "List every name and amount written on this page, one per line. Do not guess.",
        ledger_page_png(), "image/png",
    ))

    print("3) Voice Transcribe")
    wav = open(args.wav, "rb").read() if args.wav else tone_wav()
    t = mc.transcribe(wav, language_bias=["English", "Hindi"])
    print(f"   -> transcript={t.text!r} duration_ms={t.duration_ms} session={t.session_id}")

    print("4) SAM 3.1 (text prompt 'orange circle', 5 drawn)")
    raw = mc.segment(circles_png(5), "orange circle", "image/png")
    boxes = mc.parse_boxes(raw)
    print(f"   -> {len(boxes)} boxes; raw output {len(raw)} chars")
    for b in boxes:
        print(f"      box ({b.x1},{b.y1})-({b.x2},{b.y2}) c={b.confidence}")


if __name__ == "__main__":
    main()
