# SPDX-License-Identifier: Apache-2.0
"""Shared, thread-safe record of what a run has created so far.

Ten accounts acting in parallel need to react to and reply to *each other's*
messages, not just their own, so this is the one piece of state every worker
thread reads and writes. Every method takes and releases the lock itself;
nothing here is iterated outside one, so a caller can never observe a
half-updated list.
"""
import threading


class SeedState:
    def __init__(self):
        self._lock = threading.Lock()
        self._top_messages = []
        self._threads = []
        self._own_messages = {}

    def add_top_message(self, message_id, channel_id, author):
        """Records a message sent straight into the day's channel."""
        entry = {"id": message_id, "channel_id": channel_id, "author": author}
        with self._lock:
            self._top_messages.append(entry)
            self._own_messages.setdefault(author, []).append(entry)

    def add_thread(self, parent_message_id, thread_channel_id):
        with self._lock:
            self._threads.append((parent_message_id, thread_channel_id))

    def random_top_message(self, rng):
        with self._lock:
            return rng.choice(self._top_messages) if self._top_messages else None

    def random_thread(self, rng):
        """A (parent_message_id, thread_channel_id) pair, or None."""
        with self._lock:
            return rng.choice(self._threads) if self._threads else None

    def random_own_message(self, rng, author):
        with self._lock:
            pool = self._own_messages.get(author) or []
            return rng.choice(pool) if pool else None

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

    def counts(self):
        with self._lock:
            return {
                "top_messages": len(self._top_messages),
                "threads": len(self._threads),
            }
