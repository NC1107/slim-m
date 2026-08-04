# SPDX-License-Identifier: Apache-2.0
"""A generated conversation, parsed defensively before anything sends it.

`seed_ollama.load_or_generate_conversations` asks a model for a handful of
whole, structured multi-speaker conversations rather than a pool of
disconnected lines - see that module's own doc comment for why. This module
is what turns the model's raw JSON into something worth sending: `parse_
conversation` validates and coerces it, since an 8B model gets indices,
booleans and names wrong often enough that "validate, don't trust" is the
load-bearing property here. `seed_replay.replay` is the other half, split
into its own file to keep this one under the review budget - it sends the
validated result as real messages, threads and reactions.

A malformed or unusable conversation is dropped (`build_conversations`
catches and logs it) rather than raised, the same never-crash contract
`seed_ollama.py` already holds - a bad conversation just means fewer of
them, never a failed run.
"""
import dataclasses
import random
import sys

import seed_content
import seed_ollama

# Conversations per run, and the min/max accounts each draws speakers from.
DEFAULT_CONVERSATION_COUNT = 6
_PARTICIPANT_MIN = 4

# Below this many usable turns or resolved-speaker share, drop the conversation.
_MIN_TURNS = 4
_MIN_SPEAKER_MATCH_RATE = 0.5
_MAX_REACTIONS_PER_TURN = 2
_MAX_REACTORS_PER_EMOJI = 3
_FALLBACK_EMOJI = "👍"

# Grounded in both the actual product and ordinary friend-group life; see CLAUDE.md.
TOPICS = (
    "someone found a weird bug in the emoji picker and everyone starts "
    "speculating why",
    "debating whether the new voice channel icon looks better than the "
    "old one",
    "planning what to order for game night this weekend",
    "recapping a long, chaotic voice call from last night",
    "one person's self-hosted server almost went down and they're "
    "recounting the panic",
    "arguing, again, about tabs versus spaces",
    "someone shares a neat trick they found for the canvas whiteboard "
    "feature",
    "catching up after a slow week, half serious half joking",
    "planning a weekend hike or day trip",
    "reacting to a new release notes post, half excited half nitpicking",
    "someone's pet interrupted their voice call and it's the whole topic "
    "now",
    "swapping recommendations for something to watch this weekend",
    "a friendly disagreement about which pizza topping is objectively "
    "correct",
    "someone asking for help debugging a weird crash, others chiming in "
    "with guesses",
)


@dataclasses.dataclass
class Turn:
    """One line of a conversation, already resolved against real
    participants. `speaker` is `None` for a turn `parse_conversation`
    could not make sense of - kept as a placeholder rather than dropped, so
    every other turn's `reply_to`/`in_thread` index still points at the
    same position the model meant."""

    speaker: object
    text: str
    reply_to: int
    thread_root: bool
    in_thread: int
    reactions: list


@dataclasses.dataclass
class Conversation:
    topic: str
    turns: list


def _log(message):
    print(f"seed-conversation: {message}", file=sys.stderr)


def _safe_int(value, default=-1):
    """A defensive int coercion: a bool is never treated as one (Python's
    `bool` is an `int` subclass, and `True` is not a turn index), a float
    only counts if it is a whole number, and anything else that will not
    parse falls back to `default` rather than raising."""
    if isinstance(value, bool):
        return default
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, str):
        try:
            return int(value.strip())
        except ValueError:
            return default
    return default


def _resolve_speaker(raw_name, name_by_lower, participants):
    """The real participant name `raw_name` most likely means, or `None`.

    An exact case-insensitive match wins; failing that, a substring match
    either direction catches the model padding or truncating a name (`"Alan
    (seed)"`, or just `"Al"`). Genuinely unrecognisable text is `None`
    rather than a guess.
    """
    if not isinstance(raw_name, str) or not raw_name.strip():
        return None
    lowered = raw_name.strip().lower()
    if lowered in name_by_lower:
        return name_by_lower[lowered]
    for name in participants:
        if name.lower() in lowered or lowered in name.lower():
            return name
    return None


def _looks_like_emoji(text):
    """True when `text` carries no ASCII letters or digits - a rough but
    cheap way to tell an actual emoji glyph from a model writing out a word
    like "thumbsup" instead of the character."""
    return not any(ch.isascii() and ch.isalnum() for ch in text)


def _parse_reactions(raw, name_by_lower, participants, speaker):
    if not isinstance(raw, list):
        return []
    out = []
    for entry in raw[:_MAX_REACTIONS_PER_TURN]:
        if not isinstance(entry, dict):
            continue
        emoji = str(entry.get("emoji") or "").strip()
        if not emoji:
            continue
        if not _looks_like_emoji(emoji):
            emoji = _FALLBACK_EMOJI
        reactors_raw = entry.get("reactors")
        if not isinstance(reactors_raw, list):
            continue
        reactors = []
        for raw_reactor in reactors_raw[:_MAX_REACTORS_PER_EMOJI]:
            name = _resolve_speaker(raw_reactor, name_by_lower, participants)
            if name and name != speaker and name not in reactors:
                reactors.append(name)
        if reactors:
            out.append((emoji[:8], reactors))
    return out


def parse_conversation(raw):
    """A validated `Conversation`, or raises `ValueError` for one not worth
    replaying - the caller (`build_conversations`) catches this and drops
    the conversation rather than the whole run.

    Every raw turn keeps its position as a `Turn` (even an unusable one, as
    a `speaker=None` placeholder), so a later turn's `reply_to`/`in_thread`
    - a plain integer index into the model's own array - still points at
    the position the model meant, rather than a position shifted by
    whatever got dropped ahead of it.
    """
    participants = [str(p) for p in (raw.get("participants") or []) if str(p).strip()]
    if not participants:
        raise ValueError("no participants recorded for this conversation")
    raw_turns = raw.get("turns")
    if not isinstance(raw_turns, list) or len(raw_turns) < _MIN_TURNS:
        raise ValueError("fewer than the minimum usable turns")

    name_by_lower = {p.lower(): p for p in participants}
    turns = []
    usable = 0
    for item in raw_turns:
        if not isinstance(item, dict):
            turns.append(Turn(None, "", -1, False, -1, []))
            continue
        text = str(item.get("text") or "").strip()[:seed_content.MAX_MESSAGE_CHARS]
        speaker = _resolve_speaker(item.get("speaker"), name_by_lower, participants)
        if not text or speaker is None:
            turns.append(Turn(None, "", -1, False, -1, []))
            continue
        usable += 1
        turns.append(Turn(
            speaker=speaker, text=text,
            reply_to=_safe_int(item.get("reply_to")),
            thread_root=bool(item.get("thread_root")),
            in_thread=_safe_int(item.get("in_thread")),
            reactions=_parse_reactions(
                item.get("reactions"), name_by_lower, participants, speaker)))

    if usable < _MIN_TURNS or usable < len(turns) * _MIN_SPEAKER_MATCH_RATE:
        raise ValueError(
            f"only {usable}/{len(turns)} turns resolved to a real speaker")
    return Conversation(topic=str(raw.get("topic") or ""), turns=turns)


def _pick_requests(rng, accounts, count):
    """`count` `(topic, participant_names)` pairs, each a random-sized
    subset of `accounts` - see `DEFAULT_CONVERSATION_COUNT`'s own doc
    comment for why not everyone is in every conversation."""
    names = [a["display_name"] for a in accounts]
    topics = list(TOPICS)
    chosen_topics = (rng.sample(topics, k=count) if len(topics) >= count
                      else [rng.choice(topics) for _ in range(count)])
    requests = []
    for topic in chosen_topics:
        low = min(_PARTICIPANT_MIN, len(names))
        size = rng.randint(low, len(names)) if len(names) > low else len(names)
        requests.append((topic, rng.sample(names, k=size)))
    return requests


def build_conversations(model, accounts, base_seed, *,
                         count=None, ollama_base_url=None, timeout=None):
    """A list of validated `Conversation`s, or `[]` when generation is
    unavailable or produced nothing usable - never raises, the same
    contract `seed_ollama_pools.load_or_generate` holds for the corpus.

    `ollama_base_url` is where Ollama itself listens (defaults to
    `seed_ollama.DEFAULT_BASE_URL`) - never the deployment being seeded,
    which this function never talks to at all.
    """
    if not accounts:
        return []
    rng = random.Random(f"{base_seed}-conversation-topics")
    requests = _pick_requests(rng, accounts, count or DEFAULT_CONVERSATION_COUNT)
    kwargs = {}
    if ollama_base_url is not None:
        kwargs["base_url"] = ollama_base_url
    if timeout is not None:
        kwargs["timeout"] = timeout
    raw_list = seed_ollama.load_or_generate_conversations(
        model, base_seed, requests, **kwargs)

    conversations = []
    for raw in raw_list:
        try:
            conversations.append(parse_conversation(raw))
        except ValueError as exc:
            _log(f"dropping an unusable generated conversation about "
                 f"{raw.get('topic')!r}: {exc}")
    return conversations

