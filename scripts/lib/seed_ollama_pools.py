# SPDX-License-Identifier: Apache-2.0
"""The pooled `Corpus`: disconnected short/long messages, code, polls.

Split out of `seed_ollama.py` to keep that file under the review budget.
This is the corpus-specific half; `seed_ollama.py` owns the wire plumbing
both this and the conversation fetch build on (`_request`, `_reachable`,
the on-disk cache helpers), reached through the module rather than a bare
import so a test patching `seed_ollama._reachable` still reaches this call.
"""
import seed_ollama

_MAX_STRING = 2000
_MAX_CODE = 800

_SHORT_COUNT = 60
_LONG_COUNT = 24
_CODE_COUNT = 20
_POLL_COUNT = 12

_SHORT_PROMPT = (
    f"Generate {_SHORT_COUNT} short casual chat messages (roughly 4 to 14 "
    "words each) a small group of friends might send in a text channel: a "
    "mix of questions, terse acknowledgements, replies-in-tone, and "
    "enthusiastic reactions. No usernames or @ mentions." + seed_ollama._SAFETY_NOTE)
_LONG_PROMPT = (
    f"Generate {_LONG_COUNT} longer casual chat messages (roughly 4 to 8 "
    "sentences each) catching up about work, a shared project, or weekend "
    "plans, in a natural conversational tone. No usernames or @ mentions."
    + seed_ollama._SAFETY_NOTE)
_CODE_PROMPT = (
    f"Generate {_CODE_COUNT} short benign code snippets (1 to 6 lines "
    "each), spread across python, rust, bash and dart, the kind someone "
    "would casually paste into a chat to show a teammate something."
    + seed_ollama._SAFETY_NOTE)
_POLL_PROMPT = (
    f"Generate {_POLL_COUNT} short casual poll ideas a friend group chat "
    "might post (like tabs vs spaces, or where to eat), each with 2 to 4 "
    "short options." + seed_ollama._SAFETY_NOTE)

_MESSAGES_SCHEMA = {
    "type": "object",
    "properties": {"messages": {"type": "array", "items": {"type": "string"}}},
    "required": ["messages"],
}
_CODE_SCHEMA = {
    "type": "object",
    "properties": {"items": {"type": "array", "items": {
        "type": "object",
        "properties": {"lang": {"type": "string"}, "code": {"type": "string"}},
        "required": ["lang", "code"],
    }}},
    "required": ["items"],
}
_POLL_SCHEMA = {
    "type": "object",
    "properties": {"polls": {"type": "array", "items": {
        "type": "object",
        "properties": {"question": {"type": "string"},
                        "options": {"type": "array", "items": {"type": "string"}}},
        "required": ["question", "options"],
    }}},
    "required": ["polls"],
}


class Corpus:
    """A pooled batch of generated content, one list per action shape."""

    def __init__(self, short=(), long=(), code=(), polls=()):
        self.short = list(short)
        self.long = list(long)
        self.code = [tuple(item) for item in code]
        self.polls = [tuple(item) for item in polls]

    def is_empty(self):
        return not (self.short or self.long or self.code or self.polls)

    def as_dict(self):
        return {"short": self.short, "long": self.long,
                "code": self.code, "polls": self.polls}


def _fetch_messages(base_url, model, prompt, timeout):
    parsed = seed_ollama._request(base_url, model, prompt, _MESSAGES_SCHEMA, timeout)
    return [m.strip()[:_MAX_STRING] for m in parsed["messages"]
            if isinstance(m, str) and m.strip()]


def _fetch_code(base_url, model, timeout):
    parsed = seed_ollama._request(base_url, model, _CODE_PROMPT, _CODE_SCHEMA, timeout)
    out = []
    for item in parsed["items"]:
        code = (item.get("code") or "").strip()
        if not code:
            continue
        lang = (item.get("lang") or "").strip().lower() or None
        out.append((lang, code[:_MAX_CODE]))
    return out


def _fetch_polls(base_url, model, timeout):
    parsed = seed_ollama._request(base_url, model, _POLL_PROMPT, _POLL_SCHEMA, timeout)
    out = []
    for item in parsed["polls"]:
        question = (item.get("question") or "").strip()
        options = [o.strip() for o in (item.get("options") or []) if o.strip()][:4]
        if question and len(options) >= 2:
            out.append((question, options))
    return out


def _fetch_or_empty(label, fetch, *args):
    """One pool's fetch, isolated: a bad response here must not sink the rest."""
    try:
        return fetch(*args)
    except Exception as exc:  # noqa: BLE001 - one pool failing must not sink the corpus
        seed_ollama._log(f"could not generate {label}, that pool will fall back: {exc}")
        return []


def generate(base_url, model, timeout=seed_ollama._REQUEST_TIMEOUT):
    """One `Corpus`. Each pool fails independently; this call itself never
    raises."""
    return Corpus(
        short=_fetch_or_empty("short messages", _fetch_messages,
                               base_url, model, _SHORT_PROMPT, timeout),
        long=_fetch_or_empty("long messages", _fetch_messages,
                              base_url, model, _LONG_PROMPT, timeout),
        code=_fetch_or_empty("code snippets", _fetch_code,
                              base_url, model, timeout),
        polls=_fetch_or_empty("polls", _fetch_polls, base_url, model, timeout))


def _load_cache(path):
    data = seed_ollama._load_json_cache(path)
    if data is None:
        return None
    try:
        return Corpus(**data)
    except TypeError:
        return None


def _save_cache(path, corpus):
    seed_ollama._save_json_cache(path, corpus.as_dict())


def load_or_generate(model, seed, *, base_url=seed_ollama.DEFAULT_BASE_URL,
                      cache_dir=seed_ollama.CACHE_DIR,
                      timeout=seed_ollama._REQUEST_TIMEOUT):
    """A cache-first `Corpus`, or an empty one if generation is unavailable.

    Never raises: every failure is logged to stderr and answered with a
    `Corpus` some or all of whose pools are empty, which is what tells
    `seed_content.py`'s generators to fall back to their canned pools.
    """
    path = seed_ollama._cache_path(model, seed, cache_dir)
    cached = _load_cache(path)
    if cached is not None and not cached.is_empty():
        seed_ollama._log(f"using cached corpus at {path}")
        return cached

    if not seed_ollama._reachable(base_url, model):
        return Corpus()

    corpus = generate(base_url, model, timeout)
    if corpus.is_empty():
        seed_ollama._log("model returned nothing usable in any category; "
                          "falling back to canned content")
        return corpus

    _save_cache(path, corpus)
    return corpus
