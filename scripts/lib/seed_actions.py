# SPDX-License-Identifier: Apache-2.0
"""Which action a worker performs next.

Weighted rather than uniform, so a run reads like an uneven real
conversation - mostly short messages and reactions, occasionally a poll or
an attachment - rather than a flat sample across every action kind. Every
weight is a judgement call; there is nothing to derive them from.
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
