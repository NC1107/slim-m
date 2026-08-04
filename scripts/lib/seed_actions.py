# SPDX-License-Identifier: Apache-2.0
"""Which action a worker performs next.

Weighted rather than uniform, so a run reads like an uneven real
conversation - mostly short messages and reactions, occasionally a poll or
an attachment - rather than a flat sample across every action kind. Every
weight is a judgement call; there is nothing to derive them from.

`CONVERSATION_COVERED` names the chat-shaped actions a generated
conversation replay (`seed_conversation.py`/`seed_replay.py`) already
covers end to end. `seed_run.py` draws from `UTILITY_ACTIONS` instead of
`ACTIONS` only when a run actually has a conversation to replay, so a plain
or failed `--ollama` run still draws the full, unmodified set exactly as
before; `FALLBACK` and every handler stay reachable regardless, since a
rare prerequisite fallback may still land on one of the covered names.
"""

ACTIONS = (
    ("message_short", 18),
    ("message_long", 8),
    ("message_emoji", 8),
    ("message_markdown", 8),
    ("message_code_block", 5),
    ("message_mention", 8),
    ("message_near_limit", 2),
    ("message_link", 6),
    ("burst", 6),
    ("reply", 10),
    ("open_thread", 4),
    ("reply_in_thread", 8),
    ("react", 12),
    ("edit_message", 4),
    ("delete_message", 2),
    ("pin_message", 2),
    ("send_poll", 3),
    ("send_attachment", 3),
)

# What an action falls back to when its prerequisite is not met yet.
FALLBACK = "message_short"

# See the module doc comment above for what this is and why.
CONVERSATION_COVERED = frozenset({
    "message_short", "message_long", "message_emoji", "message_markdown",
    "burst", "reply", "open_thread", "reply_in_thread", "react",
})

# `ACTIONS`, minus whatever a conversation replay already covers.
UTILITY_ACTIONS = tuple(
    (name, weight) for name, weight in ACTIONS if name not in CONVERSATION_COVERED)

_NEEDS_TOP_MESSAGE = frozenset({"reply", "react", "open_thread", "pin_message"})
_OWN_MESSAGE_ACTIONS = frozenset({"edit_message", "delete_message"})


def choose_action(rng, actions=ACTIONS):
    """One action name, drawn from `actions`' weights."""
    names = [name for name, _ in actions]
    weights = [weight for _, weight in actions]
    return rng.choices(names, weights=weights, k=1)[0]


def resolve_action(action, *, has_top_message, has_own_message, has_thread,
                    has_other_account, is_privileged):
    """The action actually performed, honouring what state allows.

    A pure decision so the fallback chain is unit-testable with no server:
    the caller supplies what it already knows about the shared state rather
    than this function reaching for it.
    """
    if action in _NEEDS_TOP_MESSAGE and not has_top_message:
        return FALLBACK
    if action == "pin_message" and not is_privileged:
        return FALLBACK
    if action == "message_mention" and not has_other_account:
        return FALLBACK
    if action == "reply_in_thread" and not has_thread:
        return FALLBACK
    if action in _OWN_MESSAGE_ACTIONS and not has_own_message:
        return FALLBACK
    return action
