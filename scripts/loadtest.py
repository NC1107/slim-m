#!/usr/bin/env python3
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Holds N real sessions open against a deployment and measures the fan-out.

This exists because nothing else in the repo tests concurrency. The e2e
harness drives two browsers, and `perf/` records single-shot microbenchmarks
and idle memory, so the behaviour of a busy channel with a hundred people in
it has never been observed at all.

The first scenario is the one the code's own comments predict will hurt:
every delivered message re-derives per-connection state, so one message into
a hundred-person channel is a few hundred reads against a pool of eight
connections shared with every write.

Measured on 2026-09-15, that costs about thirty microseconds of processor
time per delivery. A hundred listeners taking two hundred and fifty messages
a second, fifty thousand deliveries, used eighteen percent of one core and
dropped nobody. The amplification is real and it is affordable.

What that run did not find is the ceiling, because this harness saturates
before the server does: a hundred listeners in one event loop is where the
measured latency starts coming from Python rather than from the server. Watch
the server's own processor time before believing a latency number this
prints. When they disagree, this harness is the one that is wrong.

Run it against a local server. Never against production: it is indistinguishable
from abuse, and the rate limiter will treat it accordingly.

    scripts/loadtest.py --base-url http://127.0.0.1:8080 --users 100

Accounts are reused across runs, so the slow registration pass is paid once
per deployment rather than per run.
"""
import argparse
import asyncio
import json
import pathlib
import sys
import time
import urllib.error

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent / "lib"))

import e2e_api  # noqa: E402
import load_report  # noqa: E402
import load_ws  # noqa: E402
import load_accounts  # noqa: E402

DEFAULT_PASSWORD = "loadtest-stable-password-1"
SETTLE_SECONDS = 5.0


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-url", default="http://127.0.0.1:8080")
    parser.add_argument("--users", type=int, default=100)
    parser.add_argument("--senders", type=int, default=5)
    parser.add_argument("--messages", type=int, default=10,
                        help="messages per sender")
    parser.add_argument("--gap", type=float, default=0.2,
                        help="seconds between one sender's messages")
    parser.add_argument("--password", default=DEFAULT_PASSWORD)
    parser.add_argument("--invite-code", default=None)
    parser.add_argument("--out", default="loadtest-result.json")
    parser.add_argument("--cache-dir", default=".",
                        help="where cached session tokens live")
    return parser.parse_args(argv)


def ws_url_for(base_url):
    return base_url.replace("https://", "wss://").replace(
        "http://", "ws://").rstrip("/") + "/ws"


def scrape(api):
    """The server's own view, or None when this caller may not read it."""
    try:
        payload = api.call("GET", "/metrics")
    except (urllib.error.HTTPError, urllib.error.URLError):
        return None
    if isinstance(payload, bytes):
        payload = payload.decode("utf-8", "replace")
    if not isinstance(payload, str):
        return None
    return load_report.parse_prometheus(payload)


def setup(args):
    """Registers or reuses the accounts, and picks the channel to crowd into."""
    print(f"setting up {args.users} accounts (cached where possible)...",
          flush=True)
    started = time.monotonic()
    accounts, from_cache = load_accounts.obtain(
        args.base_url, args.users, args.password, args.invite_code,
        args.cache_dir)
    elapsed = time.monotonic() - started
    source = "from cache" if from_cache else "freshly registered"
    print(f"  {len(accounts)} accounts ready in {elapsed:.1f}s ({source})",
          flush=True)
    admin = accounts[0]["api"]
    channels = admin.channels()
    text = [c for c in channels if c.get("kind") == "text"]
    if not text:
        raise SystemExit("no text channel to send into")
    return accounts, text[0]


async def send_phase(accounts, channel_id, args, sent_at):
    """Posts messages from each sender, recording what the REST call cost.

    `sent_at` records when the send was *started*, not when its response came
    back, because the server publishes to the socket before it finishes
    writing the HTTP response: measuring from the response makes a fast
    delivery look negative. From the start is also the number a person
    experiences, which is the one worth reporting.
    """
    senders = accounts[:args.senders]
    latencies = []

    async def one_sender(index, account):
        api = account["api"]
        for n in range(args.messages):
            body = f"loadtest s{index} m{n} {time.time():.3f}"
            started = time.monotonic()
            try:
                got = await asyncio.to_thread(
                    api.send_message, channel_id, body)
            except Exception as exc:  # noqa: BLE001 - counted, not fatal
                latencies.append(None)
                return f"send failed for sender {index}: {exc}"
            done = time.monotonic()
            latencies.append((done - started) * 1000.0)
            sent_at[got["id"]] = started
            await asyncio.sleep(args.gap)
        return None

    notes = await asyncio.gather(*(
        one_sender(i, a) for i, a in enumerate(senders)))
    return [ms for ms in latencies if ms is not None], [n for n in notes if n]


async def run(args):
    accounts, channel = setup(args)
    channel_id = channel["id"]
    admin = accounts[0]["api"]
    ws_url = ws_url_for(args.base_url)

    before = scrape(admin)
    subscribers = [load_ws.Subscriber(a["username"], a["api"], ws_url)
                   for a in accounts]
    print(f"opening {len(subscribers)} sockets...", flush=True)
    opened = await load_ws.connect_all(subscribers)
    live = [s for s, ok in zip(subscribers, opened) if ok]
    print(f"  {len(live)} of {len(subscribers)} connected", flush=True)

    seen = {}
    sent_at = {}
    stop = asyncio.Event()
    listeners = [asyncio.create_task(s.listen(seen, stop)) for s in live]

    print(f"sending {args.senders * args.messages} messages into "
          f"{channel['name']!r}...", flush=True)
    send_latencies, notes = await send_phase(
        accounts, channel_id, args, sent_at)

    await asyncio.sleep(SETTLE_SECONDS)
    stop.set()
    await asyncio.gather(*listeners, return_exceptions=True)
    after = scrape(admin)
    await asyncio.gather(*(s.close() for s in subscribers),
                         return_exceptions=True)

    delivery = []
    delivered_counts = []
    for message_id, origin in sent_at.items():
        arrivals = seen.get(message_id, [])
        delivered_counts.append(len(arrivals))
        delivery.extend((t - origin) * 1000.0 for t in arrivals)

    failures = list(notes)
    for sub in subscribers:
        if sub.failure:
            failures.append(f"{sub.name}: {sub.failure}")
    resyncs = sum(s.resync for s in subscribers)
    if resyncs:
        failures.append(f"{resyncs} subscribers were dropped and told to resync")

    expected = len(live)
    fanout = {
        "expected_per_message": expected,
        "messages": len(sent_at),
        "delivered_min": min(delivered_counts) if delivered_counts else 0,
        "delivered_max": max(delivered_counts) if delivered_counts else 0,
        "complete_messages": sum(1 for c in delivered_counts if c >= expected),
        "resyncs": resyncs,
        "total_deliveries": len(delivery),
    }
    server = {
        "delta": load_report.counter_delta(before, after),
        "rss_start_bytes": (before or {}).get(
            "slimm_process_resident_memory_bytes"),
        "rss_end_bytes": (after or {}).get(
            "slimm_process_resident_memory_bytes"),
        "ws_connections_peak": (after or {}).get("slimm_websocket_connections"),
    }
    report = load_report.build(
        "fanout-one-channel",
        {"users": len(subscribers), "connected": len(live),
         "senders": args.senders, "messages": args.senders * args.messages,
         "channel": channel["name"], "gap_seconds": args.gap},
        send_latencies, delivery, fanout, server, failures)
    load_report.write(report, args.out)
    print()
    print(load_report.render(report))
    print(f"\nwrote {args.out}")
    return report


def main(argv=None):
    args = parse_args(argv)
    if "npc-server.top" in args.base_url:
        raise SystemExit("refusing to load test the live deployment")
    asyncio.run(run(args))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
