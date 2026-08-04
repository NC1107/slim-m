# SPDX-License-Identifier: Apache-2.0
"""A final pass of activity on the newest slice of the channel.

The main loop's recency bias (`seed_state.RECENCY_BIAS`) already favours
recent targets over old ones, but that alone cannot fix a run's very last
messages: by the time they exist, there is almost no run left in which
anything could react to or reply on them. No weighting closes a shortage of
remaining actions. This runs once, after every worker has finished, against
a fixed snapshot of the newest messages and threads - never the whole
channel, or it would just move the same problem rather than fix the tail.
"""
import collections
import urllib.parse

import seed_backoff
import seed_content
import seed_worker

# How many of the newest top-level messages the pass targets.
SETTLE_TARGET_MESSAGES = 100
# Share of targets that end up with at least one reaction.
SETTLE_REACT_COVERAGE = 0.9
# Share of targets that also get a top-level reply.
SETTLE_REPLY_COVERAGE = 0.15
# How many of the most recently opened threads get kept alive.
SETTLE_THREAD_TARGETS = 10
SETTLE_THREAD_REPLIES = (1, 3)


def _actor(contexts, rng, exclude_username=None):
    """A random worker context, preferring one that is not the target's own author."""
    pool = [c for c in contexts if c.username != exclude_username] or contexts
    return rng.choice(pool)


def _react(ctx, rng, target):
    emoji = rng.choice(seed_content.EMOJI)
    encoded = urllib.parse.quote(emoji, safe="")
    return seed_backoff.call_with_backoff(
        lambda: ctx.api.call("PUT", f"/messages/{target['id']}/reactions/{encoded}"))


def _reply(ctx, rng, target):
    content = seed_content.short_message(rng, pool=seed_worker._pool(ctx, "short"))
    if target["author"] != ctx.username:
        content = f"@{target['author']} {content}"
    return seed_backoff.call_with_backoff(
        lambda: ctx.api.send_message(
            target["channel_id"], content, reply_to_id=target["id"]))


def _reply_in_thread(ctx, rng, thread_channel_id):
    content = seed_content.short_message(rng, pool=seed_worker._pool(ctx, "short"))
    return seed_backoff.call_with_backoff(
        lambda: ctx.api.send_message(thread_channel_id, content))


def _try(failures, ctx, action_name, action):
    """Runs `action`, recording rather than raising on failure - the same
    best-effort contract `seed_worker.run_account` gives every other action.

    Returns `(True, result)` on success and `(False, None)` on failure, so a
    caller that needs the created row (a reply's own id, to react to it in
    turn) can get it without a second `try`/`except` of its own.
    """
    try:
        return True, action()
    except Exception as exc:  # noqa: BLE001 - a dropped action is reported, never silent
        failures.append((ctx.username, action_name, seed_backoff.describe_error(exc)))
        return False, None


def _react_to(contexts, rng, stats, failures, reacted_ids, target):
    """One reaction draw against `target`, folded into `stats`/`reacted_ids`
    on success - the one piece of behaviour both loops below share.

    Called a second time for each reply the pass itself just created:
    that reply is now part of the newest slice too, starts exactly as bare
    as the problem this pass exists to fix, and would quietly undo the
    coverage just built if it got no chance at a reaction of its own.
    """
    if rng.random() >= SETTLE_REACT_COVERAGE:
        return
    ctx = _actor(contexts, rng, target["author"])
    ok, _result = _try(failures, ctx, "settle_react", lambda: _react(ctx, rng, target))
    if ok:
        stats["settle_react"] += 1
        reacted_ids.add(target["id"])


def run(contexts, state, rng):
    """Runs the settle pass; returns `(stats, failures)`, `run_account`'s shape.

    `stats` also carries `settle_coverage_hits`/`settle_coverage_targets`,
    which the run report reads to print the fraction of the newest messages
    that actually ended up with a reaction.
    """
    stats = collections.Counter()
    failures = []
    reacted_ids = set()

    targets = state.newest_top_messages(SETTLE_TARGET_MESSAGES)
    created_replies = []
    for target in targets:
        _react_to(contexts, rng, stats, failures, reacted_ids, target)
        if rng.random() < SETTLE_REPLY_COVERAGE:
            ctx = _actor(contexts, rng, target["author"])
            ok, msg = _try(failures, ctx, "settle_reply", lambda: _reply(ctx, rng, target))
            if ok:
                stats["settle_reply"] += 1
                created_replies.append(
                    {"id": msg["id"], "channel_id": target["channel_id"],
                     "author": ctx.username})

    # See _react_to's own doc comment for why this second pass exists.
    for reply_target in created_replies:
        _react_to(contexts, rng, stats, failures, reacted_ids, reply_target)

    for _parent_id, thread_channel_id in state.newest_threads(SETTLE_THREAD_TARGETS):
        for _ in range(rng.randint(*SETTLE_THREAD_REPLIES)):
            ctx = _actor(contexts, rng)
            ok, _result = _try(
                failures, ctx, "settle_reply_in_thread",
                lambda: _reply_in_thread(ctx, rng, thread_channel_id))
            if ok:
                stats["settle_reply_in_thread"] += 1

    stats["settle_coverage_hits"] = len(reacted_ids)
    stats["settle_coverage_targets"] = len(targets) + len(created_replies)
    return stats, failures
