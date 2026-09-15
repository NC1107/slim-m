# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Listeners spread across processes, so the harness is not the bottleneck.

A single event loop holding a hundred sockets starts contributing its own
queueing delay somewhere around twenty-five thousand deliveries in a run,
which makes every latency number past that point a measurement of Python.
Splitting the listeners across processes moves that ceiling up by roughly
the core count, which is what makes it possible to load the server until
*it* is the thing that gives way.

Arrival times cross a process boundary, which is safe here because
`time.monotonic` reads CLOCK_MONOTONIC on Linux: one system-wide clock, so
a timestamp taken in a child is directly comparable with one taken in the
parent. That is the whole reason the sender can stay in the orchestrator.
"""
import asyncio
import multiprocessing as mp
import os

import e2e_api
import load_ws


async def _run_slice(specs, base_url, ws_url, ready, stop, results):
    subscribers = []
    for username, token in specs:
        api = e2e_api.Api(base_url, token=token)
        subscribers.append(load_ws.Subscriber(username, api, ws_url))
    opened = await load_ws.connect_all(subscribers, concurrency=20)
    live = [s for s, ok in zip(subscribers, opened) if ok]

    seen = {}
    stopper = asyncio.Event()
    tasks = [asyncio.create_task(s.listen(seen, stopper)) for s in live]
    ready.put(("ready", os.getpid(), len(live), len(subscribers)))

    await asyncio.to_thread(stop.wait)
    stopper.set()
    await asyncio.gather(*tasks, return_exceptions=True)
    await asyncio.gather(*(s.close() for s in subscribers),
                         return_exceptions=True)

    results.put({
        "pid": os.getpid(),
        "connected": len(live),
        "attempted": len(subscribers),
        "seen": {mid: times for mid, times in seen.items()},
        "resyncs": sum(s.resync for s in subscribers),
        "failures": [f"{s.name}: {s.failure}" for s in subscribers
                     if s.failure],
    })


def _worker(specs, base_url, ws_url, ready, stop, results):
    try:
        asyncio.run(_run_slice(specs, base_url, ws_url, ready, stop, results))
    except Exception as exc:  # noqa: BLE001 - reported, never silent
        results.put({"pid": os.getpid(), "connected": 0,
                     "attempted": len(specs), "seen": {}, "resyncs": 0,
                     "failures": [f"worker died: {type(exc).__name__}: {exc}"]})


class ListenerPool:
    """Owns the child processes holding the sockets."""

    def __init__(self, accounts, base_url, ws_url, workers, per_account=1):
        """`per_account` sockets per account, to reach connection counts that
        enrolling one account each could never pay for.

        Nothing caps how many sockets one account may hold, and a connect
        ticket is charged to a per-user bucket that allows ten in a burst, so
        ten sockets per account is free where ten accounts costs a minute of
        address-keyed registration. It does mean a run at a high multiplier is
        testing connection handling rather than realistic per-person
        behaviour, which is the right trade for finding a ceiling.
        """
        self.base_url = base_url
        self.ws_url = ws_url
        self.workers = max(1, workers)
        self.specs = [(f"{a['username']}#{n}", a["api"].token)
                      for a in accounts for n in range(max(1, per_account))]
        self._ctx = mp.get_context("spawn")
        self._ready = self._ctx.Queue()
        self._results = self._ctx.Queue()
        self._stop = self._ctx.Event()
        self._procs = []

    def start(self, timeout=180):
        """Spawns the workers and blocks until every one has its sockets up.

        Returns how many connections actually opened, which is not always
        what was asked for: past the server's connection ceiling the excess
        is refused, and that refusal is the measurement.
        """
        slices = [self.specs[i::self.workers] for i in range(self.workers)]
        for chunk in slices:
            if not chunk:
                continue
            proc = self._ctx.Process(
                target=_worker,
                args=(chunk, self.base_url, self.ws_url, self._ready,
                      self._stop, self._results))
            proc.start()
            self._procs.append(proc)
        connected = 0
        attempted = 0
        for _ in self._procs:
            _, _, live, tried = self._ready.get(timeout=timeout)
            connected += live
            attempted += tried
        return connected, attempted

    def finish(self, timeout=180):
        """Signals stop, drains every worker, and merges what they saw."""
        self._stop.set()
        seen = {}
        resyncs = 0
        failures = []
        connected = 0
        for _ in self._procs:
            got = self._results.get(timeout=timeout)
            connected += got["connected"]
            resyncs += got["resyncs"]
            failures.extend(got["failures"])
            for message_id, times in got["seen"].items():
                seen.setdefault(message_id, []).extend(times)
        for proc in self._procs:
            proc.join(timeout=30)
            if proc.is_alive():
                proc.terminate()
        return {"seen": seen, "resyncs": resyncs, "failures": failures,
                "connected": connected}
