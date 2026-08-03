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

The 32-byte secret must be the byte-for-byte match of what the app derives
from `lib/data/trial/_secret.dart`. Store the secret at
`~/.kaitan/codegen.key` in raw hex; if missing, this script prints the
XOR combination that reproduces the current v1 app key and exits.
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
KEY_PATH = Path(os.path.expanduser("~/.kaitan/codegen.key"))

# The current v1 secret in the app is derived from the XOR of these three
# fragments. We reproduce it here so `--print-secret` (below) is authoritative.
FRAG_A = "5c81a70bc94f2d0387b5610cbe9e8d5a3fa8c40b7d1e6a9002f38b57ec4d1a29"
FRAG_B = "a34f92c611080d7b9c40db26feb17109b7423e6c5f1a290187db4e1075acbf12"
FRAG_C = "9b204ec7ee9b3e784fa5b6d21c4f5f18e29b3705a6217a37c68b4bde01e0d16b"


def _derive_v1() -> bytes:
    a = bytes.fromhex(FRAG_A)
    b = bytes.fromhex(FRAG_B)
    c = bytes.fromhex(FRAG_C)
    return bytes(x ^ y ^ z for x, y, z in zip(a, b, c))


def _load_secret() -> bytes:
    """Prefer ~/.kaitan/codegen.key (raw hex). Fall back to derived v1 key."""
    if KEY_PATH.exists():
        return bytes.fromhex(KEY_PATH.read_text().strip())
    return _derive_v1()


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
    p.add_argument("--key-version", type=int, default=1,
                   help="Which app key version to sign with (default 1).")
    p.add_argument("--out", type=Path, default=None,
                   help="CSV output path (default: codes_<UTC>.csv).")
    p.add_argument("--print-secret", action="store_true",
                   help="Print the derived v1 hex key + exit "
                        "(no codes are generated).")
    args = p.parse_args()

    if args.print_secret:
        print(_derive_v1().hex())
        return

    secret = _load_secret()
    state = load_state()
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")

    out_path = args.out or Path(f"codes_{now.replace(':', '-')}.csv")

    with out_path.open("w", newline="", encoding="utf-8") as fp:
        w = csv.writer(fp)
        w.writerow(["code", "purchase_id", "generated_at_utc", "key_version"])
        for _ in range(args.count):
            pid = state["next_id"]
            code = generate_one(pid, args.key_version, secret)
            w.writerow([code, pid, now, args.key_version])
            state["history"].append({"pid": pid, "at": now, "kv": args.key_version})
            state["next_id"] += 1

    save_state(state)
    print(f"wrote {args.count} codes → {out_path.name}")
    print(f"purchase_id range this batch: "
          f"{state['next_id'] - args.count}..{state['next_id'] - 1}")


if __name__ == "__main__":
    main()
