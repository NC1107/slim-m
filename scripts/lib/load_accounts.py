# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Getting N authenticated sessions without paying for them every run.

Registration and login share one IP-keyed bucket that allows five in a burst
and then one every six seconds, so standing up a hundred accounts costs about
ten minutes. That is worth measuring once, and worth never measuring again:
a run that spends ten minutes before it starts is a run nobody iterates on.

So tokens are cached to disk, keyed by deployment, and reused until the
server rejects one. The cache holds credentials for a throwaway local load
test and is written under the caller's chosen directory, never the repo.
"""
import json
import os
import pathlib
import urllib.error

import e2e_api
import seed_accounts


def _cache_path(directory, base_url):
    safe = "".join(c if c.isalnum() else "-" for c in base_url).strip("-")
    return pathlib.Path(directory) / f"loadtest-tokens-{safe}.json"


def _load_cache(path):
    try:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def _save_cache(path, accounts):
    payload = [{"username": a["username"], "display_name": a["display_name"],
                "token": a["api"].token} for a in accounts]
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
    os.chmod(path, 0o600)


def _still_valid(base_url, entry):
    api = e2e_api.Api(base_url, token=entry["token"])
    try:
        api.me()
        return api
    except (urllib.error.HTTPError, urllib.error.URLError):
        return None


def obtain(base_url, count, password, invite_code, cache_dir):
    """N authenticated `Api` handles, from cache where the cache still works.

    Returns `(accounts, from_cache)`. A cache that is too small, stale, or
    rejected falls back to the ordinary registration path and is rewritten,
    so a wiped server or a changed account set self-heals rather than needing
    the file deleted by hand.
    """
    path = _cache_path(cache_dir, base_url)
    cached = _load_cache(path)
    if cached and len(cached) >= count:
        revived = []
        for entry in cached[:count]:
            api = _still_valid(base_url, entry)
            if api is None:
                revived = []
                break
            revived.append({"username": entry["username"],
                            "display_name": entry["display_name"],
                            "api": api, "reused": True})
        if revived:
            return revived, True

    accounts = seed_accounts.register_accounts(
        base_url, count, password, invite_code, "loadtest", username_tag="lt")
    _save_cache(path, accounts)
    return accounts, False
