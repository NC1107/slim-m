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

import seed_accounts
import seed_guard
import seed_media
import seed_ollama
import seed_settle
import seed_state
import seed_worker

_PACE_RANGE = (0.3, 1.5)

# Wide, tall, small, a medium "screenshot", then one near the upload ceiling.
_IMAGE_SPECS = (
    ("seed-banner.png", lambda p, rng: seed_media.gradient_png(
        p, 1600, 360, (27, 111, 145), (216, 88, 55), axis="x")),
    ("seed-poster.png", lambda p, rng: seed_media.gradient_png(
        p, 360, 1600, (88, 180, 216), (33, 33, 46), axis="y")),
    ("seed-icon.png", lambda p, rng: seed_media.checkerboard_png(
        p, 40, 40, (88, 216, 120), (20, 40, 30), cell=5)),
    ("seed-screenshot.png", lambda p, rng: seed_media.rings_png(
        p, 640, 360, (216, 88, 55), (245, 230, 200), ring_width=18)),
    ("seed-large-photo.png", lambda p, rng: seed_media.noise_png(
        p, 2000, 1400, rng)),
)
_PDF_TITLE = "Release notes - overnight sync"
_PDF_LINES = (
    "Fixed the reconnect loop dropping the last few messages.",
    "Added retry with backoff on the push relay client.",
    "Bumped the SQLite busy timeout to 5 seconds.",
    "Known issue: screen share on Wayland still needs a manual source id.",
    "Next up: paginate the report queue past 200 entries.",
)
_LOG_LINES = (
    "2026-08-04T02:11:03Z INFO  slimm_server: listening on 0.0.0.0:8080",
    "2026-08-04T02:11:04Z INFO  slimm_server::db: applied 24 migrations",
    "2026-08-04T02:14:22Z WARN  slimm_server::push: relay unreachable, retrying in 5s",
    "2026-08-04T02:14:27Z INFO  slimm_server::push: relay reachable again",
    "2026-08-04T02:20:11Z INFO  slimm_server::voice: sweep removed 1 stale participant",
)
_ARCHIVE_ENTRIES = (
    ("README.txt", b"Overnight sync notes.\nSee CHANGELOG for details.\n"),
    ("config.json", b'{"retries": 3, "timeout_ms": 5000}\n'),
)


def _build_fixtures(scratch_dir, seed):
    """Every attachment fixture the run may pick from `send_attachment`:
    five PNGs (see `_IMAGE_SPECS`), one PDF, a text log, a zip archive, a
    WAV tone, and - when ffmpeg is on `PATH` - a short real mp4 clip.

    `seed-large-photo.png` targets roughly 8 MiB (80% of
    `default_attachment_max_bytes` in `crates/slimm-server/src/config.rs`),
    near a live deployment's per-upload ceiling without risking a 413 on one
    that has not raised `SLIMM_ATTACHMENT_MAX_BYTES` past that default.
    Nothing here is a file the server would refuse: see
    `scripts/seed-data.py`'s module doc for the real allowed set, sniffed
    from bytes rather than filename or declared type. Everything but the
    mp4 is stdlib-only and so always present; the mp4 is skipped with a
    printed reason, never a failure, when ffmpeg is not installed.

    `seed` makes the noise image and the wav tone reproducible under
    `--seed`, the same as every other generated fixture and message.
    """
    rng = random.Random(f"{seed}-fixtures")
    fixtures = []
    for filename, build in _IMAGE_SPECS:
        path = os.path.join(scratch_dir, filename)
        build(path, rng)
        with open(path, "rb") as handle:
            fixtures.append((handle.read(), "image/png", filename))

    pdf_path = os.path.join(scratch_dir, "seed-notes.pdf")
    seed_media.pdf(pdf_path, _PDF_TITLE, _PDF_LINES)
    with open(pdf_path, "rb") as handle:
        fixtures.append((handle.read(), "application/pdf", "seed-notes.pdf"))

    log_path = os.path.join(scratch_dir, "server.log")
    seed_media.plain_text(log_path, _LOG_LINES)
    with open(log_path, "rb") as handle:
        fixtures.append((handle.read(), "text/plain", "server.log"))

    zip_path = os.path.join(scratch_dir, "sync-notes.zip")
    seed_media.zip_archive(zip_path, _ARCHIVE_ENTRIES)
    with open(zip_path, "rb") as handle:
        fixtures.append((handle.read(), "application/zip", "sync-notes.zip"))

    wav_path = os.path.join(scratch_dir, "seed-tone.wav")
    seed_media.wav_tone(wav_path, rng)
    with open(wav_path, "rb") as handle:
        fixtures.append((handle.read(), "audio/wav", "seed-tone.wav"))

    if seed_media.ffmpeg_available():
        mp4_path = os.path.join(scratch_dir, "seed-clip.mp4")
        seed_media.mp4_clip(mp4_path)
        with open(mp4_path, "rb") as handle:
            fixtures.append((handle.read(), "video/mp4", "seed-clip.mp4"))
    else:
        print("seed-data: ffmpeg not on PATH, skipping the video/mp4 fixture")

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
        fixtures = _build_fixtures(scratch, base_seed)
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

        results.append(seed_settle.run(contexts, state, random.Random(f"{base_seed}-settle")))

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

    coverage_hits = totals.pop("settle_coverage_hits", None)
    coverage_targets = totals.pop("settle_coverage_targets", None)

    print(f"seeded {base_url}")
    print(f"channel: {channel_name!r} ({channel['id']})")
    print(f"accounts ({len(usernames)}): {', '.join(usernames)}")
    print(f"shared password: {password}")
    print(_describe_corpus(corpus))
    print(f"created: {state.counts()}")
    recency = state.recency_stats()
    if recency["rate"] is not None:
        print(f"target selection favoured recent messages/threads "
              f"{recency['rate']:.0%} of the time "
              f"({recency['from_recent_window']}/{recency['draws']} draws), "
              f"see seed_state.RECENCY_BIAS")
    if coverage_targets:
        print(f"settle pass: {coverage_hits}/{coverage_targets} of the newest "
              f"messages carry a reaction ({coverage_hits / coverage_targets:.0%})")
    print("actions performed:")
    for name in sorted(totals):
        print(f"  {name}: {totals[name]}")
    if failures:
        print(f"{len(failures)} actions failed after retrying and were skipped:")
        for username, action, reason in failures[:20]:
            print(f"  {username} / {action}: {reason}")
        if len(failures) > 20:
            print(f"  ... and {len(failures) - 20} more")
