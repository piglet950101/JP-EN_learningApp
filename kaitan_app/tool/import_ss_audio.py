"""Import the client's Second Stage recordings and attach them to their rows.

import_audio.py maps ONE file to a headword (assets/audio/0242.mp4), which is
all First Stage ever needed. Second Stage cannot use that shape: the 2026-09-08
delivery has four files for 0242 wind, three for 0773 lead and two for 0410
pray, and they belong to particular ROWS — 0410's 祈り and 祈る人 are the same
spelling read two different ways, on two different rows.

So each row carries its own list, played in order. A conjugation row gets one
file per part, which is the client's own instruction for the sets where he
recorded singles rather than a run-through:
    「１音の場合は同じものを３回使ってください」 (0773 lead > led > led)

Loudness: he asked 「音量などの調整もお願いします」. The delivered files spread
4.7 dB apart in RMS and sit quieter than the TTS voice they play alongside.

They are normalised by RMS, NOT by EBU R128 loudness, which is the obvious
choice and the wrong one here: R128 gates on a 3-second window and these clips
are 1.3-2.3 seconds, so loudnorm's integrated measurement is meaningless for
them — asked for -16 LUFS it returned files spread over 3.4 dB, wider than it
started. Measuring mean volume and applying a fixed gain, with a limiter to
absorb the transients of a short spoken word, brings the same nine files to
within 0.5 dB of each other. The originals in mp3/ are left untouched.

Run AFTER apply_ss_text_edits.py — 0773's 同音 row is keyed on the answer that
step rewrites to lead[led]　鉛、えんぴつの芯.
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROJECT_ROOT = ROOT.parent
SRC = PROJECT_ROOT / 'mp3'          # default; an entry may name another
AUDIO = ROOT / 'assets' / 'audio'   # First Stage files + their manifest
DEST = ROOT / 'assets' / 'audio' / 'ss'
SS = ROOT / 'assets' / 'content' / 'second_stage.json'
MAP = Path(__file__).with_name('ss_audio.json')

TARGET_MEAN_DB = -24.0   # RMS. -20 was louder than the TTS beside it —
                         # 「ボリュームも大きいようです」, 09-09, on 0410,
                         # 0916 and 1901. This sits inside the range the
                         # takes arrived in (-22.8 to -27.5).
PEAK_CEILING = 0.84      # linear, ≈ -1.5 dBFS
MAX_GAIN_DB = 12.0       # a quiet file is lifted, never amplified into noise


def ffmpeg() -> str:
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        return 'ffmpeg'


def measure_mean(exe: str, path: Path) -> float | None:
    """Mean (RMS) volume in dBFS, via volumedetect. None if ffmpeg fails."""
    out = subprocess.run(
        [exe, '-hide_banner', '-nostats', '-i', str(path),
         '-af', 'volumedetect', '-f', 'null', '-'],
        capture_output=True, text=True, encoding='utf-8', errors='replace')
    m = re.search(r'mean_volume:\s*(-?[\d.]+)', out.stdout + out.stderr)
    return float(m.group(1)) if m else None


def normalise(exe: str, src: Path, dst: Path) -> bool:
    """Gain the file to TARGET_MEAN_DB, limiting peaks. False if ffmpeg fails."""
    mean = measure_mean(exe, src)
    if mean is None:
        return False
    gain = min(TARGET_MEAN_DB - mean, MAX_GAIN_DB)
    r = subprocess.run(
        [exe, '-hide_banner', '-nostats', '-y', '-i', str(src),
         '-af', f'volume={gain:.2f}dB,'
                f'alimiter=limit={PEAK_CEILING}:level=disabled',
         '-ar', '44100', '-ac', '1', '-b:a', '96k', str(dst)],
        capture_output=True, text=True, encoding='utf-8', errors='replace')
    return r.returncode == 0 and dst.exists()


def main() -> int:
    if not SRC.is_dir():
        print(f'ERROR: source not found: {SRC}')
        return 1
    doc = json.loads(SS.read_text(encoding='utf-8'))
    spec = json.loads(MAP.read_text(encoding='utf-8'))['entries']
    exe = ffmpeg()

    if DEST.exists():
        shutil.rmtree(DEST)
    DEST.mkdir(parents=True, exist_ok=True)

    # Every row starts clean, so a mapping removed here really disappears.
    for row in doc['entries']:
        row.pop('audio', None)

    cache: dict[str, str] = {}   # source filename -> bundled asset path
    warnings: list[str] = []
    dropped: list[str] = []      # rows whose reading hint the recording replaces
    attached = 0
    for e in spec:
        wid = e['word_id']
        hits = [r for r in doc['entries']
                if r['word_id'] == wid
                and (e.get('match_answer') is None
                     or r.get('answer') == e['match_answer'])
                and (e.get('match_relation') is None
                     or r.get('relation') == e['match_relation'])]
        if len(hits) != 1:
            warnings.append(
                f'{wid}: {len(hits)} rows match answer='
                f'{e.get("match_answer")!r} relation={e.get("match_relation")!r}')
            continue

        assets: list[str] = []
        for name in e['files']:
            if name in cache:
                assets.append(cache[name])
                continue
            src = (PROJECT_ROOT / e.get('dir', 'mp3')) / name
            if not src.is_file():
                warnings.append(f'{wid}: missing source file {name!r}')
                continue
            out_name = f'{wid:04d}_{len(cache):02d}.mp3'
            dst = DEST / out_name
            if not normalise(exe, src, dst):
                warnings.append(f'{wid}: ffmpeg could not normalise {name!r}')
                continue
            asset = f'audio/ss/{out_name}'
            cache[name] = asset
            assets.append(asset)
            print(f'  {name:34s} -> {out_name}')

        if not assets:
            continue
        hits[0]['audio'] = assets
        # A row with a recording must show its speaker button; 0773's 活 row
        # was tts_enabled=false because it had nothing worth synthesising.
        hits[0]['tts_enabled'] = True
        # A recording supersedes any instruction about how to READ the row, so
        # the hint comes off. Leaving it on meant a playback that fell back to
        # TTS spoke katakana over the top of his own voice — 0242 「英語では
        # なく、カタカナ読みになっています」, 0916 「発音が二重になっています」.
        # It also removes the second utterance in 0773's 同音 row entirely.
        if hits[0].pop('pronunciation_hint', None) is not None:
            dropped.append(f'{wid} {hits[0].get("relation", "")!r}')
        attached += 1

    SS.write_text(json.dumps(doc, ensure_ascii=False, indent=2),
                  encoding='utf-8')
    # Headword audio. 0824 minute's 「問題の発音」 is the First Stage recording
    # on the question screen, not a Second Stage row, so it replaces the file
    # import_audio.py laid down. Re-running THAT script restores the original;
    # run build_content.py after it to put these back.
    for h in json.loads(MAP.read_text(encoding='utf-8')).get(
            'headword_overrides', []):
        src = (PROJECT_ROOT / h.get('dir', 'mp3')) / h['file']
        if not src.is_file():
            warnings.append(f'headword {h["word_id"]}: missing {h["file"]!r}')
            continue
        dst = AUDIO / f'{h["word_id"]:04d}.mp3'
        if not normalise(exe, src, dst):
            warnings.append(f'headword {h["word_id"]}: ffmpeg failed')
            continue
        man = AUDIO / 'manifest.json'
        if man.is_file():
            mj = json.loads(man.read_text(encoding='utf-8'))
            mj.setdefault('entries', {})[str(h['word_id'])] = {
                'file': dst.name, 'word': '', 'source_ext': 'mp3'}
            man.write_text(json.dumps(mj, ensure_ascii=False, indent=2),
                           encoding='utf-8')
        print(f'  headword {h["word_id"]}: {h["file"]} -> {dst.name}')

    unused = sorted({q.name for q in SRC.iterdir() if q.suffix.lower() == '.mp3'}
                    - set(cache))
    print(f'ss audio: {len(cache)} files bundled, {attached}/{len(spec)} rows')
    for dsc in dropped:
        print(f'  reading hint dropped (recording wins): {dsc}')
    for u in unused:
        print(f'  not used: {u}')
    for w in warnings:
        print(f'  WARNING: {w}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
