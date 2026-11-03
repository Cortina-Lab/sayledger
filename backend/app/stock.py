"""Shelf photo + item name -> SAM 3.1 boxes -> count + numbered overlay.

SAM finds every instance of one concept (a short noun phrase). We keep
detections above a confidence threshold, drop near-duplicate boxes, count
them in Python and draw numbered outlines so the shopkeeper can check.
The count is approximate and the UI says so.
"""

from __future__ import annotations

import base64
import io
import re

from PIL import Image, ImageDraw, ImageFont, ImageOps

from . import meta_client

MIN_CONFIDENCE = 0.5
MAX_SIDE = 1600  # downscale big phone photos before sending


class StockError(ValueError):
    pass


def clean_item(item: str) -> str:
    item = " ".join(item.split()).strip().lower()
    if not item or len(item) > 40 or not re.fullmatch(r"[\w\s'\-]+", item):
        raise StockError("Type one item name, like \"water bottle\" or \"soap\"")
    return item


def _prepare(image: bytes) -> tuple[Image.Image, bytes]:
    try:
        img = Image.open(io.BytesIO(image))
        img = ImageOps.exif_transpose(img).convert("RGB")
    except Exception:
        raise StockError("That photo couldn't be opened") from None
    img.thumbnail((MAX_SIDE, MAX_SIDE))
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=88)
    return img, buf.getvalue()


def _iou(a, b) -> float:
    ix = max(0, min(a.x2, b.x2) - max(a.x1, b.x1))
    iy = max(0, min(a.y2, b.y2) - max(a.y1, b.y1))
    inter = ix * iy
    union = (a.x2 - a.x1) * (a.y2 - a.y1) + (b.x2 - b.x1) * (b.y2 - b.y1) - inter
    return inter / union if union else 0.0


def count(image: bytes, item: str) -> dict:
    item = clean_item(item)
    img, jpeg = _prepare(image)
    raw = meta_client.segment(jpeg, item, "image/jpeg")
    boxes = [b for b in meta_client.parse_boxes(raw) if b.confidence is None or b.confidence >= MIN_CONFIDENCE]
    boxes.sort(key=lambda b: -(b.confidence or 0))
    kept = []
    for b in boxes:
        if all(_iou(b, k) < 0.6 for k in kept):
            kept.append(b)
    # Reading order: top-to-bottom rows, then left-to-right.
    kept.sort(key=lambda b: (round(b.y1 / max(1, img.height / 8)), b.x1))

    overlay = img.copy()
    draw = ImageDraw.Draw(overlay)
    sx = img.width / kept[0].w if kept and kept[0].w else 1.0
    sy = img.height / kept[0].h if kept and kept[0].h else 1.0
    stroke = max(3, img.width // 300)
    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", max(18, img.width // 40))
    except OSError:
        font = ImageFont.load_default()
    for i, b in enumerate(kept, 1):
        x1, y1, x2, y2 = b.x1 * sx, b.y1 * sy, b.x2 * sx, b.y2 * sy
        draw.rectangle((x1, y1, x2, y2), outline=(123, 30, 44), width=stroke)
        label = str(i)
        tw, th = draw.textbbox((0, 0), label, font=font)[2:]
        draw.rectangle((x1, y1, x1 + tw + 12, y1 + th + 10), fill=(123, 30, 44))
        draw.text((x1 + 6, y1 + 3), label, fill="white", font=font)
    out = io.BytesIO()
    overlay.save(out, "JPEG", quality=85)
    n = len(kept)
    return {
        "item": item,
        "count": n,
        "overlay_jpeg": base64.b64encode(out.getvalue()).decode(),
        "note": ("Approximate. Check the numbered boxes — items hidden behind others can't be counted."
                 if n else f"No {item} found. Try a closer, well-lit photo, or a different name for the item."),
    }
