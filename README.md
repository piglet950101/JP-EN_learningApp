# 快単 (Kaitan) — English Vocabulary Memorization App

Offline, on-device English vocabulary memorization app for iOS + Android, built with Flutter for 一般社団法人KAI.

## Repository layout

- **`kaitan_app/`** — the Flutter project (Dart 3.12 / Flutter 3.44, Riverpod v3, drift/SQLite).
  - `lib/` — app source
  - `assets/` — bundled content (words.json, images, audio)
  - `tool/` — Python 3.12 pipeline (Excel → JSON, image → WebP, audio bundling)
  - `test/` — 61 unit + widget + E2E tests
- **`docs/`** — specifications, screen-transition and ER diagrams, Phase 2 implementation plan.

## Build

```bash
cd kaitan_app
flutter pub get
flutter test
flutter build apk --release
```

## Data pipeline

The bundled assets are regenerated from client-supplied sources kept outside this repo (Dropbox: Excel workbooks, JPEG illustrations, MP3/WAV/MP4 pronunciation audio).

```bash
cd kaitan_app
python tool/import_excel.py               # → assets/content/words.json
python tool/apply_mnemonic_overrides.py   # docx-driven bold-range fixes
python tool/apply_word_overrides.py       # docx-driven POS / field fixes
python tool/import_images.py              # JPEG → 800×560 WebP + manifest
python tool/import_audio.py               # audio → assets/audio + manifest
```
