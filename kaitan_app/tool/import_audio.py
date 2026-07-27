"""Import client-supplied audio pronunciation files.

Reads mp3/wav/mp4 files from `Appli開発［foxgold共有］/First Stage 音声/`
whose filenames start with `{word_id} {word}.{ext}`, renames them to
`{padded_id}.{ext}` under `assets/audio/`, and writes a manifest that maps
word_id → asset path + word (for a sanity check at runtime).

The player prefers a recorded file over the pronunciation_hint TTS fallback.
"""
from __future__ import annotations
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent
SRC = PROJECT_ROOT / 'Appli開発［foxgold共有］' / 'First Stage 音声'
DEST = ROOT / 'assets' / 'audio'
MANIFEST = DEST / 'manifest.json'
WORDS_JSON = ROOT / 'assets' / 'content' / 'words.json'

VALID_EXTS = {'.mp3', '.wav', '.mp4', '.m4a', '.aac'}
NAME_RE = re.compile(r'^(\d{1,4})[ 　_-]+(.+?)\s*\.([A-Za-z0-9]+)$')


def main() -> None:
    if not SRC.is_dir():
        print(f'ERROR: source not found: {SRC}')
        return

    words = json.loads(WORDS_JSON.read_text(encoding='utf-8'))['words']
    known_ids = {w['id']: w['word'] for w in words}

    if DEST.exists():
        shutil.rmtree(DEST)
    DEST.mkdir(parents=True, exist_ok=True)

    entries: dict[str, dict[str, str]] = {}
    skipped: list[str] = []
    for src_path in sorted(SRC.iterdir()):
        if not src_path.is_file():
            continue
        ext = src_path.suffix.lower()
        if ext not in VALID_EXTS:
            skipped.append(f'unsupported ext: {src_path.name}')
            continue
        m = NAME_RE.match(src_path.name)
        if not m:
            skipped.append(f'name does not match pattern: {src_path.name}')
            continue
        wid = int(m.group(1))
        source_word = m.group(2).strip().rstrip('.').strip()
        if wid not in known_ids:
            skipped.append(f'id {wid} not in words.json: {src_path.name}')
            continue
        expected_word = known_ids[wid]
        # Loose match: source word must be a substring/prefix of the actual word
        # (client filenames sometimes contain trailing whitespace, extension typos).
        if source_word.lower() not in expected_word.lower() and \
                expected_word.lower() not in source_word.lower():
            skipped.append(
                f'word mismatch id={wid}: file="{source_word}" json="{expected_word}"')
            # Still copy — client-authoritative — but log the mismatch.
        padded = f'{wid:04d}{ext}'
        dst_path = DEST / padded
        shutil.copy2(src_path, dst_path)
        entries[str(wid)] = {
            'file': padded,
            'word': expected_word,
            'source_ext': ext[1:],
        }

    MANIFEST.write_text(
        json.dumps(
            {
                'schema_version': 1,
                'source': str(SRC.relative_to(PROJECT_ROOT)),
                'count': len(entries),
                'entries': entries,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding='utf-8',
    )
    print(f'audio bundled: {len(entries)}')
    for w in skipped:
        print(f'  SKIP/WARN: {w}')
    total_bytes = sum((DEST / e['file']).stat().st_size for e in entries.values())
    print(f'total size: {total_bytes/1024/1024:.2f} MB')


if __name__ == '__main__':
    main()
