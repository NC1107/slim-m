# SPDX-License-Identifier: Apache-2.0
"""Generates the varied message bodies a seeding run sends.

Every function takes an explicit `random.Random` rather than the module-level
`random`, so a run is reproducible end to end with `--seed` and so all of
this is testable with no network at all. Markdown syntax matches
`message_inline.dart` and `message_markdown_blocks.dart`: `**bold**`,
`*italic*`, `~~strikethrough~~`, `||spoiler||`, `> quote`, `# heading`, and a
fenced code block.
"""

MAX_MESSAGE_CHARS = 4000

EMOJI = ["😀", "😂", "🎉", "👍", "🔥", "🙌", "😅", "🤔", "😴", "🚀", "❤️", "👀"]

_TOPICS = [
    "the new release", "tonight's plan", "that bug from yesterday",
    "the deploy", "lunch", "the design review", "the roadmap",
    "the weekend", "the last standup", "the client crash", "the migration",
]
_ADJECTIVES = [
    "wild", "quiet", "chaotic", "surprisingly smooth", "long", "short",
    "unexpectedly fun", "rough", "productive", "slow", "fine",
]
_REACTS = [
    "sounds good", "not sure about that", "let's talk tomorrow",
    "already on it", "same here", "good catch", "no objections",
    "can we revisit this later", "makes sense to me", "I disagree, actually",
    "thanks for the heads up", "still looking into it",
]
_CODE_SNIPPETS = [
    ("python", "def add(a, b):\n    return a + b"),
    ("rust", "fn add(a: i32, b: i32) -> i32 {\n    a + b\n}"),
    ("bash", "for f in *.log; do\n  echo \"$f\"\ndone"),
    ("dart", "int add(int a, int b) => a + b;"),
    (None, "1 2 3\n4 5 6\n7 8 9"),
]
_POLLS = [
    ("which day works for the sync?", ["Monday", "Wednesday", "Friday"]),
    ("what should we call the release?", ["Comet", "Ferris", "Anchor", "Slate"]),
    ("tabs or spaces?", ["Tabs", "Spaces"]),
    ("where should we eat?", ["Tacos", "Pizza", "Ramen", "Sandwiches"]),
]
_FIRST_NAMES = [
    "Ada", "Grace", "Alan", "Barbara", "Linus", "Margaret", "Dennis",
    "Radia", "Ken", "Frances", "Guido", "Katherine", "Bjarne", "Hedy",
    "Vint", "Shafi",
]


def persona(index, tag=""):
    """A (username, display_name) pair for account `index`.

    `tag` namespaces a run against a deployment that already carries an
    earlier run's accounts, so seeding the same deployment twice does not
    collide on username; a caller wanting the old deterministic names
    (mainly tests) just omits it.
    """
    name = _FIRST_NAMES[index % len(_FIRST_NAMES)]
    generation = index // len(_FIRST_NAMES)
    suffix = str(generation) if generation else ""
    prefix = f"seed-{tag}-" if tag else "seed-"
    return f"{prefix}{name.lower()}{suffix}", f"{name}{f' {generation}' if suffix else ''}"


def short_message(rng):
    return f"{rng.choice(_REACTS)}."


def long_message(rng):
    sentences = [f"{rng.choice(_REACTS)}, especially about {rng.choice(_TOPICS)}."
                 for _ in range(rng.randint(6, 14))]
    return " ".join(sentences)


def emoji_message(rng):
    picked = "".join(rng.choice(EMOJI) for _ in range(rng.randint(2, 5)))
    return f"{rng.choice(_REACTS)} {picked}"


def code_block_message(rng):
    lang, code = rng.choice(_CODE_SNIPPETS)
    return f"here's what I mean:\n```{lang or ''}\n{code}\n```"


def markdown_message(rng):
    templates = (
        lambda: f"**{rng.choice(_ADJECTIVES)}** day for {rng.choice(_TOPICS)}",
        lambda: f"*{rng.choice(_ADJECTIVES)}*, honestly",
        lambda: f"> {rng.choice(_REACTS)}\nfollow-up: {rng.choice(_TOPICS)}",
        lambda: f"||{rng.choice(_REACTS)}||",
        lambda: f"~~{rng.choice(_REACTS)}~~ actually {rng.choice(_REACTS)}",
        lambda: f"# {rng.choice(_TOPICS)}\n{rng.choice(_REACTS)}",
    )
    return rng.choice(templates)()


def mention_message(rng, usernames):
    """Assumes `usernames` is non-empty; callers fall back otherwise."""
    return f"@{rng.choice(usernames)} {rng.choice(_REACTS)} about {rng.choice(_TOPICS)}"


def near_limit_message(rng):
    """Exactly `MAX_MESSAGE_CHARS`, the length the server's own cap allows."""
    body = f"({rng.choice(_TOPICS)}) "
    while len(body) < MAX_MESSAGE_CHARS:
        body += f"{rng.choice(_REACTS)}. "
    return body[:MAX_MESSAGE_CHARS]


def poll(rng):
    """A (question, options) pair for `sendPollMessage`."""
    question, options = rng.choice(_POLLS)
    return question, list(options)
