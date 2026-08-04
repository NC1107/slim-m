# SPDX-License-Identifier: Apache-2.0
"""Optional Ollama-generated message content, for less templated seed data.

Off unless `--ollama` is passed; see `seed-data.py`. A handful of batched
calls build a pooled `Corpus` up front - never one call per message, since
800 messages at one round trip each would dominate a run and hammer the
model - and the corpus is cached to disk keyed by model and seed, so a
repeat run with the same `--seed` is instant. Every failure this module can
have (unreachable, missing model, a malformed response, a slow model past
the timeout) is caught here and answered with an empty or partial `Corpus`;
`seed_content.py`'s canned generators are always the fallback, per field, so
a side feature going missing never breaks a seed run.
"""
import hashlib
import json
import os
import sys
import urllib.error
import urllib.request

DEFAULT_MODEL = "qwen3:8b"
DEFAULT_BASE_URL = "http://localhost:11434"
CACHE_DIR = os.path.join(os.path.expanduser("~"), ".cache", "slim-m-seed")

_PROBE_TIMEOUT = 5
_REQUEST_TIMEOUT = 120
_MAX_STRING = 2000
_MAX_CODE = 800

_SHORT_COUNT = 60
_LONG_COUNT = 24
_CODE_COUNT = 20
_POLL_COUNT = 12

# Applied to every prompt below: this lands in the owner's real deployment.
_SAFETY_NOTE = (
    " Keep it benign: no passwords, API keys, tokens, or anything that "
    "looks like a real credential; no real names, addresses or private "
    "information; nothing abusive or explicit."
)
_SHORT_PROMPT = (
    f"Generate {_SHORT_COUNT} short casual chat messages (roughly 4 to 14 "
    "words each) a small group of friends might send in a text channel: a "
    "mix of questions, terse acknowledgements, replies-in-tone, and "
    "enthusiastic reactions. No usernames or @ mentions." + _SAFETY_NOTE)
_LONG_PROMPT = (
    f"Generate {_LONG_COUNT} longer casual chat messages (roughly 4 to 8 "
    "sentences each) catching up about work, a shared project, or weekend "
    "plans, in a natural conversational tone. No usernames or @ mentions."
    + _SAFETY_NOTE)
_CODE_PROMPT = (
    f"Generate {_CODE_COUNT} short benign code snippets (1 to 6 lines "
    "each), spread across python, rust, bash and dart, the kind someone "
    "would casually paste into a chat to show a teammate something."
    + _SAFETY_NOTE)
_POLL_PROMPT = (
    f"Generate {_POLL_COUNT} short casual poll ideas a friend group chat "
    "might post (like tabs vs spaces, or where to eat), each with 2 to 4 "
    "short options." + _SAFETY_NOTE)

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


def _log(message):
    print(f"seed-ollama: {message}", file=sys.stderr)


def _cache_path(model, seed, cache_dir):
    safe_model = "".join(c if c.isalnum() else "-" for c in model)
    key = hashlib.sha256(f"{model}:{seed}".encode()).hexdigest()[:16]
    return os.path.join(cache_dir, f"corpus-{safe_model}-{key}.json")


def _request(base_url, model, prompt, schema, timeout):
    body = {"model": model, "prompt": prompt, "stream": False,
            "think": False, "format": schema}
    req = urllib.request.Request(
        f"{base_url.rstrip('/')}/api/generate", data=json.dumps(body).encode(),
        method="POST", headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as res:
        payload = json.load(res)
    return json.loads(payload["response"])


def _fetch_messages(base_url, model, prompt, timeout):
    parsed = _request(base_url, model, prompt, _MESSAGES_SCHEMA, timeout)
    return [m.strip()[:_MAX_STRING] for m in parsed["messages"]
            if isinstance(m, str) and m.strip()]


def _fetch_code(base_url, model, timeout):
    parsed = _request(base_url, model, _CODE_PROMPT, _CODE_SCHEMA, timeout)
    out = []
    for item in parsed["items"]:
        code = (item.get("code") or "").strip()
        if not code:
            continue
        lang = (item.get("lang") or "").strip().lower() or None
        out.append((lang, code[:_MAX_CODE]))
    return out


def _fetch_polls(base_url, model, timeout):
    parsed = _request(base_url, model, _POLL_PROMPT, _POLL_SCHEMA, timeout)
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
        _log(f"could not generate {label}, that pool will fall back: {exc}")
        return []


def _reachable(base_url, model):
    """A quick, short-timeout check, so an outage fails fast rather than
    waiting out four full generation timeouts in a row."""
    try:
        req = urllib.request.Request(f"{base_url.rstrip('/')}/api/tags")
        with urllib.request.urlopen(req, timeout=_PROBE_TIMEOUT) as res:
            tags = json.load(res)
    except Exception as exc:  # noqa: BLE001 - unreachable is exactly what this checks for
        _log(f"could not reach {base_url}: {exc}")
        return False
    names = {m.get("name") or m.get("model") for m in tags.get("models", [])}
    if model not in names:
        _log(f"model {model!r} is not pulled on {base_url}")
        return False
    return True


def generate(base_url, model, timeout=_REQUEST_TIMEOUT):
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
    try:
        with open(path, encoding="utf-8") as fh:
            return Corpus(**json.load(fh))
    except (OSError, ValueError, TypeError, KeyError):
        return None


def _save_cache(path, corpus):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(corpus.as_dict(), fh)
    except OSError as exc:
        _log(f"could not write corpus cache: {exc}")


def load_or_generate(model, seed, *, base_url=DEFAULT_BASE_URL,
                      cache_dir=CACHE_DIR, timeout=_REQUEST_TIMEOUT):
    """A cache-first `Corpus`, or an empty one if generation is unavailable.

    Never raises: every failure is logged to stderr and answered with a
    `Corpus` some or all of whose pools are empty, which is what tells
    `seed_content.py`'s generators to fall back to their canned pools.
    """
    path = _cache_path(model, seed, cache_dir)
    cached = _load_cache(path)
    if cached is not None and not cached.is_empty():
        _log(f"using cached corpus at {path}")
        return cached

    if not _reachable(base_url, model):
        return Corpus()

    corpus = generate(base_url, model, timeout)
    if corpus.is_empty():
        _log("model returned nothing usable in any category; "
             "falling back to canned content")
        return corpus

    _save_cache(path, corpus)
    return corpus
