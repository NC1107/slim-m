# SPDX-License-Identifier: Apache-2.0
"""Orchestrates a seeding run end to end.

Guards the target, sets up accounts and a channel, then lets every account
act in parallel (one thread each, one `Api`, one rate-limit bucket) until
each has spent its turn budget. Nothing here fabricates a timestamp: the
server stamps every write with its own clock, so a run cannot backdate
messages into earlier days to force a day-divider - see the module doc on
`seed-data.py` for what that means for a single run's history.
"""
import concurrent.futures
import datetime
import os
import random
import secrets
import sys
import tempfile

import e2e_fixtures
import seed_accounts
import seed_guard
import seed_ollama
import seed_state
import seed_worker

_FIXTURE_VARIANTS = (
    ("seed-photo.png", 120, 80, (27, 111, 145)),
    ("seed-diagram.png", 200, 60, (216, 88, 55)),
    ("seed-icon.png", 32, 32, (88, 216, 120)),
)
_PACE_RANGE = (0.3, 1.5)


def _build_fixtures(scratch_dir):
    fixtures = []
    for filename, width, height, rgb in _FIXTURE_VARIANTS:
        path = os.path.join(scratch_dir, filename)
        e2e_fixtures.png(path, width, height, rgb)
        with open(path, "rb") as handle:
            fixtures.append((handle.read(), "image/png", filename))
    return fixtures


def _worker_accounts(accounts, admin_api, admin_username):
    """Seed accounts plus the admin, if one logged in, as its own worker."""
    workers = list(accounts)
    if admin_api is not None:
        workers.append({"username": admin_username, "api": admin_api})
    return workers


def run(args):
    try:
        base_url = seed_guard.guard(
            args.base_url, os.environ.get("SLIM_SEED_BASE_URL"),
            args.confirm, args.i_know_this_is_production)
    except seed_guard.GuardError as exc:
        sys.exit(f"refusing to run: {exc}")

    if args.accounts < 1:
        sys.exit("refusing to run: --accounts must be at least 1")

    password = args.password or secrets.token_urlsafe(16)
    username_tag = args.username_tag or secrets.token_hex(3)

    try:
        invite_code, admin_api = seed_accounts.obtain_invite_code(
            base_url, args.accounts, args.invite_code,
            args.admin_username, args.admin_password, "seed")
        accounts = seed_accounts.register_accounts(
            base_url, args.accounts, password, invite_code, "seed",
            username_tag=username_tag)
        channel_name = args.channel_name or datetime.date.today().isoformat()
        channel = seed_accounts.create_seed_channel(
            accounts, admin_api, channel_name)
    except seed_accounts.AccountSetupError as exc:
        sys.exit(f"refusing to continue: {exc}")

    workers = _worker_accounts(accounts, admin_api, args.admin_username)
    privileged_username = workers[-1]["username"] if admin_api else workers[0]["username"]
    usernames = [w["username"] for w in workers]
    concurrency = args.concurrency or len(workers)
    base_seed = args.seed if args.seed is not None else secrets.randbits(32)

    corpus = None
    if args.ollama:
        corpus = seed_ollama.load_or_generate(
            args.ollama_model or seed_ollama.DEFAULT_MODEL, base_seed)

    with tempfile.TemporaryDirectory(prefix="slimm-seed-") as scratch:
        fixtures = _build_fixtures(scratch)
        state = seed_state.SeedState()
        contexts = [
            seed_worker.WorkerContext(
                api=worker["api"], username=worker["username"],
                channel_id=channel["id"], state=state,
                rng=random.Random(f"{base_seed}-{index}"),
                other_usernames=[u for u in usernames if u != worker["username"]],
                is_privileged=(worker["username"] == privileged_username),
                fixtures=fixtures, corpus=corpus)
            for index, worker in enumerate(workers)
        ]

        results = []
        with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:
            futures = [
                pool.submit(seed_worker.run_account, ctx,
                            args.actions_per_account, _PACE_RANGE)
                for ctx in contexts
            ]
            for future in concurrent.futures.as_completed(futures):
                results.append(future.result())

    _report(base_url, channel, channel_name, usernames, password, state, results, corpus)
    return 0


def _describe_corpus(corpus):
    """One line on whether ollama content was actually used, not just asked
    for - a run with `--ollama` and an unreachable server still succeeds, so
    the report is where that silence would otherwise go unnoticed."""
    if corpus is None:
        return "ollama content: not requested"
    if corpus.is_empty():
        return "ollama content: requested but unavailable, used canned content"
    return (f"ollama content: {len(corpus.short)} short, {len(corpus.long)} long, "
            f"{len(corpus.code)} code, {len(corpus.polls)} poll pool entries")


def _report(base_url, channel, channel_name, usernames, password, state, results,
            corpus=None):
    totals = {}
    failures = []
    for stats, worker_failures in results:
        for name, count in stats.items():
            totals[name] = totals.get(name, 0) + count
        failures.extend(worker_failures)

    print(f"seeded {base_url}")
    print(f"channel: {channel_name!r} ({channel['id']})")
    print(f"accounts ({len(usernames)}): {', '.join(usernames)}")
    print(f"shared password: {password}")
    print(_describe_corpus(corpus))
    print(f"created: {state.counts()}")
    print("actions performed:")
    for name in sorted(totals):
        print(f"  {name}: {totals[name]}")
    if failures:
        print(f"{len(failures)} actions failed after retrying and were skipped:")
        for username, action, reason in failures[:20]:
            print(f"  {username} / {action}: {reason}")
        if len(failures) > 20:
            print(f"  ... and {len(failures) - 20} more")
