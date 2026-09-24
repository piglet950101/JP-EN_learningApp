"""
Kaitan trial-unlock code generator (offline CLI).

Usage:
    python tool/generate_codes.py --count 50
    python tool/generate_codes.py --count 100 --out codes_2026-08-04.csv

Generates N unlock codes, appends purchase_id entries to `codes_state.json`
so IDs never repeat across runs, and writes a CSV with columns:
    code, purchase_id, generated_at (UTC ISO 8601), key_version

Code layout (must match lib/data/trial/unlock_verifier.dart):
    payload = purchase_id (4 B, big-endian) || key_version (1 B)
    mac     = HMAC-SHA256(SECRET, payload)[:5]
    code    = base32(payload || mac).strip('=') formatted XXXX-XXXX-XXXX-XXXX

The 32-byte secret must be the byte-for-byte match of what the app compiles
in. It lives at `~/.kaitan/codegen.key` in raw hex and is deliberately NOT in
this repository: the v1 key used to be hardcoded here as FRAG_A/B/C, the
repository is public, and anyone could read it and mint unlimited codes. Run
`python tool/make_secret.py` to produce the matching `_secret.dart`.
"""

from __future__ import annotations
import argparse
import base64
import csv
import hmac
import hashlib
import json
import os
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

STATE = Path(__file__).with_name("codes_state.json")

# First purchase_id of the standalone series (codes sold without the set).
# Must equal kStandaloneSeriesFirstId in lib/data/trial/code_series.dart;
# test/store_release_test.dart checks the two agree.
STANDALONE_FIRST_ID = 1_000_000
KEY_PATH = Path(os.path.expanduser("~/.kaitan/codegen.key"))

def _load_secret() -> bytes:
    """Read ~/.kaitan/codegen.key (raw hex). No fallback, by design.

    There used to be a fallback to a key hardcoded in this file. That is what
    published the v1 key. A missing key file must now be a hard error, not a
    quiet substitution — signing codes with the wrong key produces codes that
    look fine and never work.
    """
    if not KEY_PATH.exists():
        raise SystemExit(
            f"no signing key at {KEY_PATH}. "
            "Run `python tool/make_secret.py --init` (first time) or copy the "
            "key file from whoever holds it.")
    key = bytes.fromhex(KEY_PATH.read_text(encoding="utf-8").strip())
    if len(key) != 32:
        raise SystemExit(f"key must be 32 bytes, got {len(key)}")
    return key


def _base32(bs: bytes) -> str:
    return base64.b32encode(bs).decode("ascii").rstrip("=")


def _format(code_body: str) -> str:
    """Chunk 16 chars into XXXX-XXXX-XXXX-XXXX."""
    return "-".join(code_body[i:i + 4] for i in range(0, len(code_body), 4))


def generate_one(purchase_id: int, key_version: int, secret: bytes) -> str:
    payload = struct.pack(">IB", purchase_id, key_version)  # 4 + 1 = 5 bytes
    mac = hmac.new(secret, payload, hashlib.sha256).digest()[:5]
    code_bytes = payload + mac
    return _format(_base32(code_bytes))


def load_state() -> dict:
    if STATE.exists():
        return json.loads(STATE.read_text(encoding="utf-8"))
    return {"schema_version": 1, "next_id": 1, "history": []}


def save_state(state: dict) -> None:
    STATE.write_text(json.dumps(state, indent=2), encoding="utf-8")


def main() -> None:
    p = argparse.ArgumentParser(description="Generate Kaitan unlock codes.")
    p.add_argument("--count", type=int, default=10,
                   help="How many codes to generate this run.")
    p.add_argument("--key-version", type=int, default=2,
                   help="Which app key version to sign with (default 2). v1 was rotated out on 2026-09-15 and no longer verifies.")
    p.add_argument("--out", type=Path, default=None,
                   help="CSV output path (default: codes_<UTC>.csv).")
    p.add_argument("--standalone", action="store_true",
                   help="Issue from the standalone series: codes sold on their "
                        "own, WITHOUT the physical set. The iOS build rejects "
                        "these (App Review 3.1.1 bans a license-key unlock; "
                        "3.1.4 covers only codes that come with the set). "
                        "Numbered from STANDALONE_FIRST_ID, which must match "
                        "kStandaloneSeriesFirstId in lib/data/trial/code_series.dart.")
    args = p.parse_args()

    secret = _load_secret()
    state = load_state()
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")

    counter = "next_standalone_id" if args.standalone else "next_id"
    state.setdefault("next_standalone_id", STANDALONE_FIRST_ID)
    first = state[counter]
    # Checked before anything is written: a CSV of valid codes that the state
    # file never recorded would be issued twice by the next run.
    if not args.standalone and first + args.count - 1 >= STANDALONE_FIRST_ID:
        sys.exit("this batch would run the set series into the standalone "
                 "range; stop and renumber before issuing more")

    out_path = args.out or Path(f"codes_{now.replace(':', '-')}.csv")

    with out_path.open("w", newline="", encoding="utf-8") as fp:
        w = csv.writer(fp)
        w.writerow(["code", "purchase_id", "generated_at_utc", "key_version"])
        for _ in range(args.count):
            pid = state[counter]
            code = generate_one(pid, args.key_version, secret)
            w.writerow([code, pid, now, args.key_version])
            entry = {"pid": pid, "at": now, "kv": args.key_version}
            if args.standalone:
                entry["series"] = "standalone"
            state["history"].append(entry)
            state[counter] += 1

    save_state(state)
    series = "standalone (NOT accepted on iOS)" if args.standalone else "set"
    print(f"wrote {args.count} codes → {out_path.name}")
    print(f"series: {series}")
    print(f"purchase_id range this batch: {first}..{state[counter] - 1}")


if __name__ == "__main__":
    main()
