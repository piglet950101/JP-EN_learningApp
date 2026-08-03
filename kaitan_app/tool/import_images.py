"""
Image pipeline for 「快単」.

Walks the client-supplied image folders, normalizes each illustration
to WebP (max 800x560, q80, no upscale), normalizes filenames to the
canonical 4-digit global word ID, and emits a manifest.

Supports BOTH source conventions the client has used:

  • FLAT (current, since 2026-06-02):
        Appli開発［foxgold共有］/快単vol.1・2画像*/<global_id>.jpg
        e.g. 0001.jpg, 0042.jpg, 2201.jpg

  • PER-BLOCK (early sample, 2026-05-22):
        Appli開発［foxgold共有］/快単vol.<X>画像/<start>-<end>/Ⅱ-<N>.jpg
        where N is 1..count within the block; global_id = start + (N - 1)

When both layouts coexist, FLAT files win (treated as more authoritative).

Output:
    kaitan_app/assets/images/{:04d}.webp
    kaitan_app/assets/images/manifest.json   (lists IDs that have illustrations)

The Flutter side uses manifest.json to decide whether to render an
Image.asset on the ⑦ Answer screen or fall back to a clean placeholder
slot — so missing IDs never produce broken-image UI.

Re-running this script is idempotent: existing .webp files are overwritten
in place. Adding more images later = drop them in the source folder + rerun.
"""

from __future__ import annotations
import json
import re
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Pillow not installed. Run: python -m pip install Pillow", file=sys.stderr)
    sys.exit(2)

# ── paths & policy ──────────────────────────────────────────────────────
ROOT = Path(__file__).resolve().parents[2]            # …/20260521_english_app
SRC_PARENT = ROOT / "Appli開発［foxgold共有］"
OUT_DIR = Path(__file__).resolve().parents[1] / "assets" / "images"
MANIFEST = OUT_DIR / "manifest.json"

MAX_W, MAX_H = 800, 560     # display target on phones; phones rarely need more
WEBP_QUALITY = 80           # visually indistinguishable for cartoon-style art
WEBP_METHOD = 6             # 0=fast..6=slow; 6 = best compression (one-time cost)

# Naming patterns
# FLAT layout: the global word ID is the LEADING 1-4 digits; an optional
# hyphenated suffix follows (e.g. "0349-Ⅱ-2.jpg", "0911-02.jpg",
# "0976-02-02.jpg" — confirmed-existing variants in the live folder).
# We always prefer "NNNN.jpg" over a suffixed variant if both exist for the
# same global id (see _discover_flat below).
FLAT_FILE_RE = re.compile(r"^(\d{1,4})(?:[-_].+)?\.(jpe?g|png)$", re.IGNORECASE)
PER_BLOCK_FOLDER_RE = re.compile(r"^(\d+)\s*[-–~〜]\s*(\d+)$")  # "1-48", "49-96"
PER_BLOCK_FILE_RE = re.compile(
    r"^[ⅡⅠⅢⅣⅤⅥⅦⅧⅨⅩ]\s*[-–]\s*(\d+)\s*\.(jpe?g|png)$",
    re.IGNORECASE,
)
# 医系ブロック (2026-07-27): filenames are "{id}{word}.png" — digits immediately
# followed by the English word with no separator, e.g. "2202pneumonia.png".
MEDICAL_FILE_RE = re.compile(r"^(\d{4})[A-Za-z].*\.(png|jpe?g)$", re.IGNORECASE)
MAX_ID = 2267  # 1..2267 (vol.1: 1..1100, vol.2: 1101..2201, vol.3 医系: 2202..2267)


# ── discovery ───────────────────────────────────────────────────────────
def _discover_flat():
    """Yield (global_id, source_path, 'flat') for flat-layout folders.
    Matches any subfolder of SRC_PARENT whose name begins with '快単vol' and
    contains image files. A file's leading 1-4 digits are the global ID;
    optional hyphenated suffixes are accepted (e.g. '0349-Ⅱ-2.jpg').

    When multiple files map to the same ID (plain + suffix variant), the
    file with the SHORTEST name wins — i.e. plain 'NNNN.jpg' beats
    'NNNN-foo.jpg'. This matches the client's intended naming."""
    for folder in sorted(SRC_PARENT.iterdir()):
        if not folder.is_dir():
            continue
        # FLAT folder names so far seen: "快単vol.1・2画像0001～2201JPEG"
        if not (folder.name.startswith("快単vol") and "・" in folder.name):
            continue
        by_id: dict[int, Path] = {}
        for img in sorted(folder.iterdir()):
            if not img.is_file():
                continue
            m = FLAT_FILE_RE.match(img.name)
            if not m:
                continue
            gid = int(m.group(1))
            if not (1 <= gid <= MAX_ID):
                print(f"  skip (id out of range 1..{MAX_ID}): {img.name}")
                continue
            existing = by_id.get(gid)
            # Prefer the shorter (more canonical) filename.
            if existing is None or len(img.name) < len(existing.name):
                by_id[gid] = img
        for gid in sorted(by_id):
            yield gid, by_id[gid], "flat"


def _discover_medical():
    """Yield (global_id, source_path, 'medical') for the vol.3 medical
    vocabulary folder. Naming convention (client-provided 2026-07-27):
        医系単語2202-2267Second Stage画像/{id}{word}.png
    e.g. 2202pneumonia.png. IDs 2202..2267 accepted."""
    for folder in sorted(SRC_PARENT.iterdir()):
        if not folder.is_dir():
            continue
        if not folder.name.startswith("医系単語"):
            continue
        for img in sorted(folder.iterdir()):
            if not img.is_file():
                continue
            m = MEDICAL_FILE_RE.match(img.name)
            if not m:
                print(f"  skip (medical: bad name): {img.name}")
                continue
            gid = int(m.group(1))
            if not (2202 <= gid <= 2267):
                print(f"  skip (medical: id out of range 2202..2267): {img.name}")
                continue
            yield gid, img, "medical"


def _discover_per_block():
    """Yield (global_id, source_path, 'per_block') for the early sample layout."""
    for vol_dir in sorted(SRC_PARENT.iterdir()):
        if not vol_dir.is_dir():
            continue
        vol_match = re.fullmatch(r"快単vol\.(\d+)画像", vol_dir.name)
        if not vol_match:
            continue
        for block_dir in sorted(vol_dir.iterdir()):
            if not block_dir.is_dir():
                continue
            fm = PER_BLOCK_FOLDER_RE.match(block_dir.name)
            if not fm:
                print(f"  skip folder (bad name): {block_dir.name}")
                continue
            start_id, end_id = int(fm.group(1)), int(fm.group(2))
            for img in sorted(block_dir.iterdir()):
                if not img.is_file():
                    continue
                m = PER_BLOCK_FILE_RE.match(img.name)
                if not m:
                    print(f"  skip file (bad name): {img.relative_to(SRC_PARENT)}")
                    continue
                position = int(m.group(1))
                gid = start_id + position - 1
                if gid > end_id:
                    print(f"  skip (position out of folder range): {img.name}")
                    continue
                yield gid, img, "per_block"


def discover_sources():
    """Discover from BOTH layouts. Flat-layout entries win on collision."""
    if not SRC_PARENT.exists():
        print(f"NOT FOUND: {SRC_PARENT}", file=sys.stderr)
        sys.exit(1)

    chosen: dict[int, tuple[Path, str]] = {}
    # 1) Per-block first so flat wins on overwrite.
    for gid, path, layout in _discover_per_block():
        chosen[gid] = (path, layout)
    flat_overrides = 0
    for gid, path, layout in _discover_flat():
        if gid in chosen and chosen[gid][1] == "per_block":
            flat_overrides += 1
        chosen[gid] = (path, layout)
    # Medical (vol.3, 2202..2267) — separate folder & naming, no collisions with
    # vol.1/2 flat layout (which is capped at 2201).
    for gid, path, layout in _discover_medical():
        chosen[gid] = (path, layout)

    if flat_overrides:
        print(f"  note: {flat_overrides} flat-layout files override per-block "
              "variants (newer authoritative naming)")

    for gid in sorted(chosen):
        path, _layout = chosen[gid]
        yield gid, path, _layout


# ── conversion ──────────────────────────────────────────────────────────
def convert_one(global_id: int, src_path: Path):
    """Convert one source → WebP. Returns (src_bytes, out_bytes, out_dims)."""
    out_path = OUT_DIR / f"{global_id:04d}.webp"
    with Image.open(src_path) as im:
        # WebP supports RGBA but the cartoons have no transparency; drop alpha
        # for smaller files and to flatten any source quirks.
        if im.mode not in ("RGB",):
            im = im.convert("RGB")
        # thumbnail() shrinks-only — never upscales — and preserves aspect ratio.
        im.thumbnail((MAX_W, MAX_H), Image.Resampling.LANCZOS)
        im.save(
            out_path,
            format="WEBP",
            quality=WEBP_QUALITY,
            method=WEBP_METHOD,
        )
        return src_path.stat().st_size, out_path.stat().st_size, im.size


# ── main ────────────────────────────────────────────────────────────────
def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    items = list(discover_sources())
    if not items:
        print("No source images discovered. Nothing to do.")
        # Still write an (empty) manifest so the app doesn't crash on load.
        MANIFEST.write_text(
            json.dumps({"schema_version": 1, "ids": [], "count": 0},
                       ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        return

    # Detect collisions (same global_id from multiple files) before doing work.
    seen: dict[int, Path] = {}
    for gid, path, _vol in items:
        if gid in seen and seen[gid] != path:
            print(f"  collision: id={gid:04d}  {seen[gid].name}  vs  {path.name}")
        seen[gid] = path

    print(f"Discovered {len(seen)} images. Converting → {OUT_DIR.relative_to(ROOT)}")

    total_src = 0
    total_out = 0
    converted_ids: list[int] = []
    for gid in sorted(seen.keys()):
        src = seen[gid]
        try:
            sb, ob, dims = convert_one(gid, src)
        except Exception as e:                           # noqa: BLE001
            print(f"  FAIL {gid:04d}: {e}")
            continue
        converted_ids.append(gid)
        total_src += sb
        total_out += ob
        if len(converted_ids) % 8 == 0 or len(converted_ids) == len(seen):
            print(f"  [{len(converted_ids):>4d}/{len(seen)}] "
                  f"{gid:04d}.webp  "
                  f"{sb // 1024:>4d}KB → {ob // 1024:>3d}KB  "
                  f"({dims[0]}x{dims[1]})")

    manifest = {
        "schema_version": 1,
        "max_width": MAX_W,
        "max_height": MAX_H,
        "webp_quality": WEBP_QUALITY,
        "count": len(converted_ids),
        "ids": converted_ids,
    }
    MANIFEST.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    print()
    print(f"Converted: {len(converted_ids)} images")
    print(f"Source:    {total_src / 1024 / 1024:>6.2f} MB")
    print(f"Output:    {total_out / 1024 / 1024:>6.2f} MB"
          f"  ({(1 - total_out / total_src) * 100:.1f}% smaller)")
    print(f"Manifest:  {MANIFEST.relative_to(ROOT)}")
    if converted_ids:
        print(f"ID range:  {min(converted_ids):04d}..{max(converted_ids):04d}")


if __name__ == "__main__":
    main()
