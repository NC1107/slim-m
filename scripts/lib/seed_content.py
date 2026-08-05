# SPDX-License-Identifier: Apache-2.0
"""Generates the varied message bodies a seeding run sends.

Every function takes an explicit `random.Random` rather than the module-level
`random`, so a run is reproducible end to end with `--seed` and so all of
this is testable with no network at all. Markdown syntax matches
`message_inline.dart` and `message_markdown_blocks.dart`: `**bold**`,
`*italic*`, `~~strikethrough~~`, `||spoiler||`, `> quote`, `# heading`, and a
fenced code block.

Every generator below also takes an optional `pool`: a shaped list from
`seed_ollama_pools.Corpus`, drawn from when non-empty, so a `--ollama` run's
utility actions (the ones a generated conversation does not already cover;
see `seed_conversation.py`) read less templated. `pool` is `None` (or
empty) for a plain run, and every function falls back to its own canned
content exactly as before - the two paths are the same functions, not a
parallel implementation to drift from.
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
    ("python",
     "def binary_search(items, target):\n"
     "    low, high = 0, len(items) - 1\n"
     "    while low <= high:\n"
     "        mid = (low + high) // 2\n"
     "        if items[mid] == target:\n"
     "            return mid\n"
     "        if items[mid] < target:\n"
     "            low = mid + 1\n"
     "        else:\n"
     "            high = mid - 1\n"
     "    return -1\n"
     "\n"
     "\n"
     "def chunked(iterable, size):\n"
     "    chunk = []\n"
     "    for item in iterable:\n"
     "        chunk.append(item)\n"
     "        if len(chunk) == size:\n"
     "            yield chunk\n"
     "            chunk = []\n"
     "    if chunk:\n"
     "        yield chunk"),
    ("rust",
     "use std::thread::sleep;\n"
     "use std::time::Duration;\n"
     "\n"
     "fn retry_with_backoff<T, E>(\n"
     "    mut attempts: u32,\n"
     "    mut op: impl FnMut() -> Result<T, E>,\n"
     ") -> Result<T, E> {\n"
     "    let mut delay = Duration::from_millis(100);\n"
     "    loop {\n"
     "        match op() {\n"
     "            Ok(value) => return Ok(value),\n"
     "            Err(err) => {\n"
     "                attempts -= 1;\n"
     "                if attempts == 0 {\n"
     "                    return Err(err);\n"
     "                }\n"
     "                sleep(delay);\n"
     "                delay *= 2;\n"
     "            }\n"
     "        }\n"
     "    }\n"
     "}"),
    ("dart",
     "class Debouncer {\n"
     "  Debouncer(this.delay);\n"
     "\n"
     "  final Duration delay;\n"
     "  Timer? _timer;\n"
     "\n"
     "  void run(void Function() action) {\n"
     "    _timer?.cancel();\n"
     "    _timer = Timer(delay, action);\n"
     "  }\n"
     "\n"
     "  void dispose() {\n"
     "    _timer?.cancel();\n"
     "    _timer = null;\n"
     "  }\n"
     "}"),
    ("bash",
     "#!/usr/bin/env bash\n"
     "set -euo pipefail\n"
     "backup_dir=\"$1\"\n"
     "max_age_days=\"${2:-7}\"\n"
     "timestamp=$(date +%Y%m%d-%H%M%S)\n"
     "mkdir -p \"$backup_dir/archive\"\n"
     "for file in \"$backup_dir\"/*.log; do\n"
     "  [ -f \"$file\" ] || continue\n"
     "  age_days=$(( ( $(date +%s) - $(stat -c %Y \"$file\") ) / 86400 ))\n"
     "  if [ \"$age_days\" -gt \"$max_age_days\" ]; then\n"
     "    gzip -c \"$file\" > \"$backup_dir/archive/$(basename \"$file\").$timestamp.gz\"\n"
     "    rm \"$file\"\n"
     "  fi\n"
     "done"),
    ("javascript",
     "async function fetchWithRetry(url, options = {}, retries = 3, delayMs = 300) {\n"
     "  for (let attempt = 0; attempt < retries; attempt++) {\n"
     "    try {\n"
     "      const response = await fetch(url, options);\n"
     "      if (!response.ok) {\n"
     "        throw new Error(`request failed with status ${response.status}`);\n"
     "      }\n"
     "      return await response.json();\n"
     "    } catch (err) {\n"
     "      if (attempt === retries - 1) {\n"
     "        throw err;\n"
     "      }\n"
     "      await new Promise((resolve) => setTimeout(resolve, delayMs * (attempt + 1)));\n"
     "    }\n"
     "  }\n"
     "}"),
    ("go",
     "func processInParallel(jobs []int, workers int, fn func(int) int) []int {\n"
     "    results := make([]int, len(jobs))\n"
     "    jobCh := make(chan int, len(jobs))\n"
     "    var wg sync.WaitGroup\n"
     "\n"
     "    for i := range jobs {\n"
     "        jobCh <- i\n"
     "    }\n"
     "    close(jobCh)\n"
     "\n"
     "    for w := 0; w < workers; w++ {\n"
     "        wg.Add(1)\n"
     "        go func() {\n"
     "            defer wg.Done()\n"
     "            for i := range jobCh {\n"
     "                results[i] = fn(jobs[i])\n"
     "            }\n"
     "        }()\n"
     "    }\n"
     "    wg.Wait()\n"
     "    return results\n"
     "}"),
    ("sql",
     "WITH active_users AS (\n"
     "  SELECT id, username\n"
     "  FROM users\n"
     "  WHERE deleted_at IS NULL\n"
     ")\n"
     "SELECT au.username,\n"
     "       COUNT(m.id) AS message_count,\n"
     "       MAX(m.created_at) AS last_message_at\n"
     "FROM active_users au\n"
     "LEFT JOIN messages m ON m.author_id = au.id AND m.deleted_at IS NULL\n"
     "GROUP BY au.id\n"
     "HAVING COUNT(m.id) > 0\n"
     "ORDER BY message_count DESC\n"
     "LIMIT 20;"),
    (None,
     "2026-08-04T02:14:07Z INFO  starting server on 0.0.0.0:8080\n"
     "2026-08-04T02:14:07Z INFO  connected to sqlite at data/slimm.db\n"
     "2026-08-04T02:14:12Z WARN  rate limit bucket exhausted for 10.0.0.42\n"
     "2026-08-04T02:15:03Z ERROR failed to deliver push: relay unreachable\n"
     "2026-08-04T02:15:03Z INFO  retrying push delivery in 30s\n"
     "2026-08-04T02:15:34Z INFO  push delivered after 1 retry"),
    ("csv",
     "id,username,messages_sent,joined_at\n"
     "1,ada,482,2026-01-04\n"
     "2,grace,290,2026-01-09\n"
     "3,linus,701,2025-12-22\n"
     "4,margaret,133,2026-02-14\n"
     "5,dennis,58,2026-03-01"),
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


_MARKDOWN_WRAPPERS = (
    lambda text: f"**{text}**",
    lambda text: f"*{text}*",
    lambda text: f"> {text}",
    lambda text: f"||{text}||",
    lambda text: f"~~{text}~~",
    lambda text: f"# {text}",
)


def short_message(rng, pool=None):
    if pool:
        return rng.choice(pool)
    return f"{rng.choice(_REACTS)}."


def long_message(rng, pool=None):
    if pool:
        return rng.choice(pool)
    sentences = [f"{rng.choice(_REACTS)}, especially about {rng.choice(_TOPICS)}."
                 for _ in range(rng.randint(6, 14))]
    return " ".join(sentences)


def emoji_message(rng, pool=None):
    picked = "".join(rng.choice(EMOJI) for _ in range(rng.randint(2, 5)))
    text = rng.choice(pool) if pool else rng.choice(_REACTS)
    return f"{text} {picked}"


# A real paste is often bare, and an intro is not always the same phrase.
_CODE_INTROS = (
    "here's what I mean:",
    "quick snippet:",
    "something like this:",
    "found this earlier, might help:",
    "for reference:",
    "this is roughly what I had:",
)
_NO_INTRO_CHANCE = 0.3


def code_block_message(rng, pool=None):
    lang, code = rng.choice(pool) if pool else rng.choice(_CODE_SNIPPETS)
    fence = f"```{lang or ''}\n{code}\n```"
    if rng.random() < _NO_INTRO_CHANCE:
        return fence
    return f"{rng.choice(_CODE_INTROS)}\n{fence}"


def markdown_message(rng, pool=None):
    if pool:
        return rng.choice(_MARKDOWN_WRAPPERS)(rng.choice(pool))
    templates = (
        lambda: f"**{rng.choice(_ADJECTIVES)}** day for {rng.choice(_TOPICS)}",
        lambda: f"*{rng.choice(_ADJECTIVES)}*, honestly",
        lambda: f"> {rng.choice(_REACTS)}\nfollow-up: {rng.choice(_TOPICS)}",
        lambda: f"||{rng.choice(_REACTS)}||",
        lambda: f"~~{rng.choice(_REACTS)}~~ actually {rng.choice(_REACTS)}",
        lambda: f"# {rng.choice(_TOPICS)}\n{rng.choice(_REACTS)}",
    )
    return rng.choice(templates)()


def mention_message(rng, usernames, pool=None):
    """Assumes `usernames` is non-empty; callers fall back otherwise."""
    if pool:
        return f"@{rng.choice(usernames)} {rng.choice(pool)}"
    return f"@{rng.choice(usernames)} {rng.choice(_REACTS)} about {rng.choice(_TOPICS)}"


def near_limit_message(rng, pool=None):
    """Exactly `MAX_MESSAGE_CHARS`, the length the server's own cap allows."""
    sentences = pool if pool else None
    body = f"({rng.choice(_TOPICS)}) "
    while len(body) < MAX_MESSAGE_CHARS:
        body += f"{rng.choice(sentences)} " if sentences else f"{rng.choice(_REACTS)}. "
    return body[:MAX_MESSAGE_CHARS]


def poll(rng, pool=None):
    """A (question, options) pair for `sendPollMessage`."""
    question, options = rng.choice(pool) if pool else rng.choice(_POLLS)
    return question, list(options)
