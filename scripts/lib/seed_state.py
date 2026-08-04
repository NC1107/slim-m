# SPDX-License-Identifier: Apache-2.0
"""Shared, thread-safe record of what a run has created so far.

Ten accounts acting in parallel need to react to and reply to *each other's*
messages, not just their own, so this is the one piece of state every worker
thread reads and writes. Every method takes and releases the lock itself;
nothing here is iterated outside one, so a caller can never observe a
half-updated list.

Every pool here is append-only, so a pool's tail is always its newest
entries: `random_top_message`, `random_thread` and `random_own_message` all
draw through `_recency_choice` rather than `rng.choice`, or a run's earliest
messages - eligible the longest, and for the most draws - would soak up
nearly every reaction and reply while the screenful anyone actually opens a
channel to stays bare. See `recency_stats()` for how to check it worked.
"""
import threading

# How many of a pool's newest entries count as "recent" for a draw.
RECENT_WINDOW = 30
# Share of draws favouring RECENT_WINDOW; the rest are the long tail.
RECENCY_BIAS = 0.85


def _recency_choice(rng, pool):
    """One entry from `pool`, biased toward its newest `RECENT_WINDOW`.

    Returns `(entry, from_recent_window)` so a caller can track the bias
    that actually happened, not just the one that was configured.
    """
    if not pool:
        return None, False
    if rng.random() < RECENCY_BIAS:
        return rng.choice(pool[-RECENT_WINDOW:]), True
    return rng.choice(pool), False


class SeedState:
    def __init__(self):
        self._lock = threading.Lock()
        self._top_messages = []
        self._threads = []
        self._own_messages = {}
        self._recency_draws = 0
        self._recency_hits = 0

    def add_top_message(self, message_id, channel_id, author):
        """Records a message sent straight into the day's channel."""
        entry = {"id": message_id, "channel_id": channel_id, "author": author}
        with self._lock:
            self._top_messages.append(entry)
            self._own_messages.setdefault(author, []).append(entry)

    def add_thread(self, parent_message_id, thread_channel_id):
        with self._lock:
            self._threads.append((parent_message_id, thread_channel_id))

    def _draw(self, rng, pool):
        """Runs `_recency_choice` and folds its outcome into `recency_stats()`.

        An empty pool counts toward neither: there was no bias to apply, so
        it would only dilute the reported rate away from what was actually
        configured.
        """
        entry, from_recent = _recency_choice(rng, pool)
        if entry is not None:
            self._recency_draws += 1
            if from_recent:
                self._recency_hits += 1
        return entry

    def random_top_message(self, rng):
        with self._lock:
            return self._draw(rng, self._top_messages)

    def random_thread(self, rng):
        """A (parent_message_id, thread_channel_id) pair, or None.

        Threads are recorded in the order they were opened, so favouring
        the pool's tail here specifically favours *recently opened* threads
        - the ones a `reply_in_thread` draw should keep alive rather than
        letting go quiet the moment something newer opens.
        """
        with self._lock:
            return self._draw(rng, self._threads)

    def random_own_message(self, rng, author):
        with self._lock:
            pool = self._own_messages.get(author) or []
            return self._draw(rng, pool)

    def forget_own_message(self, author, message_id):
        """Drops a deleted message so it is never targeted again."""
        with self._lock:
            pool = self._own_messages.get(author)
            if pool:
                self._own_messages[author] = [
                    m for m in pool if m["id"] != message_id]

    def has_top_message(self):
        with self._lock:
            return bool(self._top_messages)

    def has_thread(self):
        with self._lock:
            return bool(self._threads)

    def newest_top_messages(self, count):
        """A fixed snapshot of the newest `count` top-level messages.

        Unlike `random_top_message`, this is not a draw: it is the settle
        pass's window, taken once so a fixed set of targets stays fixed
        while the pass runs, rather than sliding under it as replies land.
        """
        with self._lock:
            return list(self._top_messages[-count:])

    def newest_threads(self, count):
        """A fixed snapshot of the newest `count` opened threads."""
        with self._lock:
            return list(self._threads[-count:])

    def counts(self):
        with self._lock:
            return {
                "top_messages": len(self._top_messages),
                "threads": len(self._threads),
            }

    def recency_stats(self):
        """How often a target draw actually landed in the recent window.

        Printed in the run report so the bias is a measured fact about the
        run rather than a silent change in behaviour: a rate near
        `RECENCY_BIAS` says the weighting did what it was configured to do.
        """
        with self._lock:
            draws, hits = self._recency_draws, self._recency_hits
        return {
            "draws": draws,
            "from_recent_window": hits,
            "rate": (hits / draws) if draws else None,
        }
