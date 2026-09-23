#!/usr/bin/env python3
"""A slim-m bot that answers `!retry-test` with `pong`, exactly like bot-ping,
except its `send()` is retry-safe rather than fire-and-forget.

Run it with a bot token from Space settings -> Bots:

    pip install websockets
    SLIMM_URL=https://your.space SLIMM_BOT_TOKEN=slimbot_... python3 bot.py

The point of this example is `send_with_retry()`, not the trigger. Every other
example in this repo calls the messages route once and lets a network hiccup
turn into a lost reply. `docs/bots/building-bots.md` already says a send is
idempotent by its client-supplied id and that a retry after a timeout is
safe - this is the first example that actually retries, and README.md records
what was verified live against a running deployment before this shipped: real
concurrent duplicate sends, a connection abandoned before and after the
server had time to act on it, and the same id reused across a channel and an
author, none of which duplicated or lost a message.

See README.md for the retry contract this implements and what it deliberately
leaves out.
"""

import asyncio
import json
import os
import random
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

import websockets

BASE = os.environ.get("SLIMM_URL", "").rstrip("/")
TOKEN = os.environ.get("SLIMM_BOT_TOKEN", "")
PROTOCOL = 1
TRIGGER = "!retry-test"
REPLY = "pong"
# urllib's default UA is blocked by a CDN before it ever reaches slim-m.
USER_AGENT = "slimm-bot-retry/1.0"

MAX_ATTEMPTS = 6
BASE_DELAY_SECONDS = 0.5
MAX_DELAY_SECONDS = 20.0


def call(method, path, body=None):
    """One authenticated REST call, returning parsed JSON or None for 204."""
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(f"{BASE}{path}", data=data, method=method)
    request.add_header("authorization", f"Bearer {TOKEN}")
    request.add_header("user-agent", USER_AGENT)
    if data is not None:
        request.add_header("content-type", "application/json")
    with urllib.request.urlopen(request, timeout=15) as response:
        raw = response.read()
        return json.loads(raw) if raw else None


def _should_retry(err):
    """Whether `err` means "try again" rather than "this request is rejected".

    A 5xx or 429 means the outcome is the server's problem, not this
    request's; anything else in 4xx means the request itself was rejected and
    an unchanged retry would just be rejected again. A plain rate-limit 429
    (`ApiError::TooManyRequests` in `crates/slimm-server/src/http/error.rs`)
    carries no `Retry-After` to honour - verified live against a running
    deployment - unlike slow mode's own 429, which does; this backs off on a
    fixed schedule instead of trying to read a header that is not there.
    A `URLError`/`OSError` with no status at all is a connection failure:
    always worth retrying, since nothing here says the request was rejected.
    """
    if isinstance(err, urllib.error.HTTPError):
        return err.code == 429 or err.code >= 500
    return isinstance(err, (urllib.error.URLError, TimeoutError, OSError))


def send_with_retry(channel_id, content, max_attempts=MAX_ATTEMPTS):
    """Post a message, retrying an uncertain failure without ever changing id.

    The id is generated once, before the first attempt, and every retry
    reuses it. That single fact is the whole guarantee: a retry of a send
    that actually landed returns the message already stored
    (`crates/slimm-server/src/store/messages.rs::Store::send_message`, which
    takes SQLite's write lock up front so concurrent attempts on one id queue
    rather than race - see that function's own doc comment). Regenerating the
    id on retry would defeat this and is the single most common way to get a
    bot's retry logic wrong.

    Never vary `content` between attempts under one id - the server replays
    whatever it first stored, whatever a later attempt carries, so passing
    different content here on a real retry would silently be ignored rather
    than doing what you might expect.
    """
    message_id = str(uuid.uuid4())
    delay = BASE_DELAY_SECONDS
    last_err = None
    for attempt in range(max_attempts):
        try:
            return call(
                "POST",
                f"/channels/{channel_id}/messages",
                {"id": message_id, "content": content},
            )
        except (urllib.error.HTTPError, urllib.error.URLError, OSError) as err:
            last_err = err
            if not _should_retry(err):
                raise
            if attempt == max_attempts - 1:
                break
            sleep_for = min(delay, MAX_DELAY_SECONDS) + random.uniform(0, 0.25)
            print(f"send failed ({err}), retrying in {sleep_for:.1f}s", file=sys.stderr)
            time.sleep(sleep_for)
            delay *= 2
    raise last_err


def socket_url(base):
    """The WebSocket URL for `base`, refusing to carry a token in plaintext."""
    parts = urllib.parse.urlsplit(base)
    if parts.scheme == "https":
        return urllib.parse.urlunsplit(("wss", parts.netloc, "/ws", "", ""))
    if parts.scheme == "http" and parts.hostname in ("localhost", "127.0.0.1", "::1"):
        print("warning: plaintext ws, loopback only", file=sys.stderr)
        return urllib.parse.urlunsplit(("ws", parts.netloc, "/ws", "", ""))
    raise RuntimeError(
        f"refusing to send a bot token over {parts.scheme or 'no'} scheme to "
        f"{parts.hostname or base}; use https"
    )


def should_answer(message, me):
    """A `!retry-test` from somebody other than us; see "Answering yourself"."""
    if message.get("author_id") == me:
        return False
    return (message.get("content") or "").strip().lower().startswith(TRIGGER)


async def listen():
    me = call("GET", "/me")["id"]
    print(f"connected as {me}", flush=True)

    ticket = call("POST", "/auth/ws-ticket")["ticket"]
    ws_url = socket_url(BASE)

    async with websockets.connect(ws_url, user_agent_header=USER_AGENT) as socket:
        await socket.send(
            json.dumps({"type": "hello", "ticket": ticket, "protocol": PROTOCOL})
        )
        hello = json.loads(await socket.recv())
        if hello.get("type") != "hello":
            raise RuntimeError(f"expected a hello back, got {hello}")
        print("listening", flush=True)

        async for raw in socket:
            frame = json.loads(raw)
            if frame.get("type") != "message.created":
                continue
            message = frame.get("message") or {}
            if should_answer(message, me):
                send_with_retry(frame["channel_id"], REPLY)
                print(f"answered in {frame['channel_id']}", flush=True)


async def main():
    if not BASE or not TOKEN:
        print("set SLIMM_URL and SLIMM_BOT_TOKEN", file=sys.stderr)
        return 2
    while True:
        try:
            await listen()
        except urllib.error.HTTPError as err:
            if err.code == 401:
                print("token rejected - revoked?", file=sys.stderr)
                return 1
            print(f"http {err.code}, reconnecting", file=sys.stderr)
        except Exception as err:
            print(f"{type(err).__name__}: {err}, reconnecting", file=sys.stderr)
        await asyncio.sleep(3)


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()) or 0)
