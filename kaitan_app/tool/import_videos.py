"""
Vimeo URL list -> videos.json for 快単 (Kaitan).

Input : tool/videos_source.json   (curated by AKAME; client sends URLs via email)
Output: assets/content/videos.json

Splits each Vimeo unlisted-share URL
    https://vimeo.com/{ID}/{HASH}?fl=tl&fe=ec
into its id and hash, so the Flutter side can construct the embed URL
    https://player.vimeo.com/video/{ID}?h={HASH}
without having to parse strings at runtime.
"""

from __future__ import annotations
import json
import re
import sys
from pathlib import Path

SRC = Path(__file__).with_name("videos_source.json")
OUT = Path(__file__).resolve().parents[1] / "assets" / "content" / "videos.json"
WORDS_JSON = Path(__file__).resolve().parents[1] / "assets" / "content" / "words.json"

# Vimeo unlisted-share format: vimeo.com/{ID}/{HASH}?…
# Both id and hash are alphanumeric; hash is typically 10 chars.
URL_RE = re.compile(r"^https?://(?:www\.)?vimeo\.com/(\d+)/([A-Za-z0-9]+)")


_ORIENTATION_RATIOS = {"portrait": 9 / 16, "vertical": 9 / 16,
                       "landscape": 16 / 9, "horizontal": 16 / 9,
                       "square": 1.0}


def _aspect_of(item):
    """Width-over-height for one source entry, or None if not declared."""
    raw = item.get("aspect_ratio")
    if isinstance(raw, (int, float)) and raw > 0:
        return round(float(raw), 6)
    if isinstance(raw, str) and ":" in raw:          # "9:16"
        w, _, h = raw.partition(":")
        try:
            if float(h) > 0:
                return round(float(w) / float(h), 6)
        except ValueError:
            pass
    o = str(item.get("orientation", "")).strip().lower()
    return _ORIENTATION_RATIOS.get(o)


def _vol_of_block(block: int) -> int:
    return 1 if block <= 23 else 2  # 46-block core; medical block (47) has no video


def _title_of(block: int) -> str:
    return f"第{block}ブロック 解説"


def main() -> None:
    if not SRC.exists():
        print(f"ERROR: source not found: {SRC}", file=sys.stderr)
        sys.exit(2)
    src = json.loads(SRC.read_text(encoding="utf-8"))
    words = json.loads(WORDS_JSON.read_text(encoding="utf-8"))["words"]
    word_ids_by_block: dict[int, list[int]] = {}
    for w in words:
        word_ids_by_block.setdefault(w["block"], []).append(w["id"])

    seen_blocks: set[int] = set()
    entries: list[dict] = []
    warnings: list[str] = []

    for i, item in enumerate(src["urls"], start=1):
        block = item["block"]
        url = item["url"]
        if block in seen_blocks:
            warnings.append(f"duplicate block {block} in videos_source.json")
        seen_blocks.add(block)
        m = URL_RE.match(url)
        if not m:
            warnings.append(f"unparseable Vimeo URL for block {block}: {url}")
            continue
        vimeo_id, vimeo_hash = m.group(1), m.group(2)
        # Word-id range within the block, for the video-detail "この動画で扱う語彙".
        ids = sorted(word_ids_by_block.get(block, []))
        entries.append({
            "id": i,
            "block": block,
            "vol": _vol_of_block(block),
            "title": _title_of(block),
            "vimeo_id": vimeo_id,
            "vimeo_hash": vimeo_hash,
            "embed_url": f"https://player.vimeo.com/video/{vimeo_id}?h={vimeo_hash}",
            "share_url": url,
            "duration_sec": item.get("duration_sec"),   # client-supplied estimate, may be null
            # Shape of the footage. The first 46 videos are genuine 16:9, but
            # the client shoots vertically as well, so the source may declare
            # either an explicit ratio or just "portrait"/"landscape". Null
            # means "unknown" and the app falls back to 16:9.
            "aspect_ratio": _aspect_of(item),
            "first_word_id": ids[0] if ids else None,
            "last_word_id": ids[-1] if ids else None,
        })

    # Cross-check that we have exactly one video per block 1..46.
    missing_blocks = [b for b in range(1, 47) if b not in seen_blocks]
    if missing_blocks:
        warnings.append(f"blocks with no video URL: {missing_blocks}")

    entries.sort(key=lambda e: e["block"])
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "schema_version": 1,
        "source": SRC.name,
        "count": len(entries),
        "vimeo_privacy": "unlisted-share (hash required)",
        "warnings_count": len(warnings),
        "entries": entries,
    }, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"wrote {OUT.name}  entries={len(entries)} (blocks 1..46)")
    for w in warnings:
        print(f"  WARN: {w}")


if __name__ == "__main__":
    main()
