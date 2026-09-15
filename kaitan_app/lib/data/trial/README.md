# Unlock-code signing key

`_secret.dart` is **not in this repository** and must not be added to it.

It is generated from a key held outside the repo:

```
python tool/make_secret.py          # writes _secret.dart from ~/.kaitan/codegen.key
python tool/make_secret.py --init   # first machine only: mint a new key
```

If the build fails with *Target of URI doesn't exist: '_secret.dart'*, run the
first command. If it then says there is no key, you need the key file from
whoever holds it — send it privately, never through this repository, an issue,
or a chat log.

## Why

The key signs the unlock codes that open every block. Verification is entirely
offline and there is no server, so a code that works cannot be withdrawn.

Until 2026-09-15 the key was committed twice — as XOR fragments here and in
clear as `FRAG_A/B/C` in `tool/generate_codes.py` — while the repository was
public. Both were readable without a login, so anyone who found them could
issue unlimited valid codes for a ¥29,800 product.

Deleting the files does not fix that: git history keeps them, and anyone may
already have a clone. The fix was to rotate to a key that was never published
(**version 2**) and to keep it out of the repo from now on. Codes signed with
v1 no longer verify.

## Rotating again

Bump `KEY_VERSION` in `tool/make_secret.py`, run `--init --force`, rebuild and
ship. Every code signed with an older version stops working the moment users
update, so only do this while no outstanding code needs to keep working.
