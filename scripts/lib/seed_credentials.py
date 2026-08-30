# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""A stable seed-account password, persisted across runs.

Account reuse (see `seed_accounts.py`) works by trying to register each
persona and falling back to a login when the username is already taken -
which only succeeds if the login uses the *same* password an earlier run
registered it with. So the default password, whenever a caller does not
pass `--password` explicitly, has to be the same across runs too, not a
fresh random one every time. Cached under `~/.cache/slim-m-seed/`, the same
directory `seed_ollama.py` already caches its corpus in, keyed by the
target's own base URL so seeding two different deployments never collides
on one shared password.
"""
import hashlib
import json
import os
import secrets

CACHE_DIR = os.path.join(os.path.expanduser("~"), ".cache", "slim-m-seed")


def _cache_path(base_url, cache_dir):
    key = hashlib.sha256(base_url.encode()).hexdigest()[:16]
    return os.path.join(cache_dir, f"password-{key}.json")


def load_or_create(base_url, *, cache_dir=CACHE_DIR):
    """The same password on every call for one `base_url`.

    Never raises: a cache read or write failure just means the password is
    regenerated (or not persisted for next time), not a reason to stop the
    run - the same tolerant shape `seed_ollama.py`'s cache already has.
    """
    path = _cache_path(base_url, cache_dir)
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)["password"]
    except (OSError, ValueError, KeyError):
        pass

    password = secrets.token_urlsafe(16)
    try:
        os.makedirs(cache_dir, exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump({"password": password}, fh)
    except OSError:
        pass
    return password
