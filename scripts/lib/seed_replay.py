# SPDX-License-Identifier: Apache-2.0
"""Sends a parsed `seed_conversation.Conversation` as real API calls.

Split out of `seed_conversation.py` to keep that file under the review
budget: that module is about turning a model's raw JSON into something
trustworthy, this one is about turning a trusted `Conversation` into
messages, threads and reactions on the real server, in order, from the real
seed accounts.
"""
import collections
import time
import urllib.parse

import seed_backoff
import seed_content


def _try(failures, ctx, action_name, action):
    """Runs `action`, recording rather than raising on failure - the same
    best-effort contract every other seeding pass gives an individual step.
    """
    try:
        return True, action()
    except Exception as exc:  # noqa: BLE001 - a dropped action is reported, never silent
        failures.append((ctx["username"], action_name, seed_backoff.describe_error(exc)))
        return False, None


def _send(ctx, channel_id, text, reply_to_id):
    return seed_backoff.call_with_backoff(
        lambda: ctx["api"].send_message(channel_id, text, reply_to_id))


def _open_thread(ctx, channel_id, message_id):
    return seed_backoff.call_with_backoff(
        lambda: ctx["api"].open_thread(channel_id, message_id))


def _react(ctx, message_id, emoji):
    encoded = urllib.parse.quote(emoji, safe="")
    return seed_backoff.call_with_backoff(
        lambda: ctx["api"].call("PUT", f"/messages/{message_id}/reactions/{encoded}"))


def replay(conversation, accounts_by_display, main_channel_id, state, rng,
           pace_range=(0.25, 0.8)):
    """Sends `conversation` as real messages, threads and reactions, from
    the real accounts in `accounts_by_display` (keyed by display name, the
    shape `seed_accounts.register_accounts` returns).

    Returns `(stats, failures)`, the same shape every other seeding pass
    reports in. A turn whose `reply_to`/`in_thread` reference turned out to
    be wrong or unresolved falls back to the most recent applicable message
    in the same channel scope, rather than losing the reply/thread
    structure the model at least attempted - see the inline comments below.
    """
    stats = collections.Counter()
    failures = []
    turn_message_ids = {}
    turn_channel_ids = {}
    turn_authors = {}
    thread_channel_for = {}
    most_recent_thread_idx = None
    most_recent_in_channel = {}

    for idx, turn in enumerate(conversation.turns):
        if turn.speaker is None:
            continue
        ctx = accounts_by_display.get(turn.speaker)
        if ctx is None:
            continue

        # Falls back to the most recent thread, then the main channel.
        target_channel = main_channel_id
        if turn.in_thread >= 0:
            target_channel = thread_channel_for.get(turn.in_thread)
            if target_channel is None and most_recent_thread_idx is not None:
                target_channel = thread_channel_for.get(most_recent_thread_idx)
            if target_channel is None:
                target_channel = main_channel_id

        reply_to_id = None
        reply_to_author = None
        if turn.reply_to >= 0:
            if turn_channel_ids.get(turn.reply_to) == target_channel:
                reply_to_id = turn_message_ids.get(turn.reply_to)
                reply_to_author = turn_authors.get(turn.reply_to)
            elif target_channel in most_recent_in_channel:
                reply_to_id, reply_to_author = most_recent_in_channel[target_channel]

        text = turn.text
        if reply_to_id is not None and reply_to_author and reply_to_author != ctx["username"]:
            text = f"@{reply_to_author} {text}"[:seed_content.MAX_MESSAGE_CHARS]

        ok, msg = _try(failures, ctx, "conversation_message",
                        lambda ctx=ctx, target_channel=target_channel, text=text,
                        reply_to_id=reply_to_id: _send(ctx, target_channel, text, reply_to_id))
        time.sleep(rng.uniform(*pace_range))
        if not ok:
            continue
        stats["conversation_message"] += 1
        turn_message_ids[idx] = msg["id"]
        turn_channel_ids[idx] = target_channel
        turn_authors[idx] = ctx["username"]
        most_recent_in_channel[target_channel] = (msg["id"], ctx["username"])

        if target_channel == main_channel_id:
            state.add_top_message(msg["id"], main_channel_id, ctx["username"])
            if turn.thread_root:
                ok, thread = _try(
                    failures, ctx, "conversation_open_thread",
                    lambda ctx=ctx, mid=msg["id"]: _open_thread(ctx, main_channel_id, mid))
                if ok:
                    stats["conversation_open_thread"] += 1
                    thread_channel_for[idx] = thread["id"]
                    most_recent_thread_idx = idx
                    state.add_thread(msg["id"], thread["id"])

        for emoji, reactor_names in turn.reactions:
            for name in reactor_names:
                reactor = accounts_by_display.get(name)
                if reactor is None:
                    continue
                ok, _result = _try(
                    failures, reactor, "conversation_react",
                    lambda reactor=reactor, emoji=emoji, mid=msg["id"]:
                        _react(reactor, mid, emoji))
                if ok:
                    stats["conversation_react"] += 1

    return stats, failures
