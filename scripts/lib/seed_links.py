# SPDX-License-Identifier: Apache-2.0
"""Link-bearing message content: video, article, image, and repo URLs.

Split out of seed_content.py rather than added to it, to keep that file
under its review budget once its code corpus grew from one-liners to real
functions - see CLAUDE.md's file-budget rule and this project's own history
of splitting a file in the change that would cross it.

Every URL below is real and points at something durable, safe, and unlikely
to ever disappear: Wikipedia, MDN, a well-known open-source repository, a
canonical example YouTube video, or picsum.photos's placeholder-image
service, never a generated or throwaway domain - these end up as literal
message text in a real deployment, so they are worth getting right rather
than fabricating a fake-looking URL.

Every URL is filed under exactly one category (`_LINKS_BY_CATEGORY`), and an
intro is drawn from that category's own pool rather than a shared one, or a
picsum image URL can end up captioned "worth a watch" the way a real run
once showed - a category mismatch reads worse than a repeated phrase does.
Some fraction of messages carry no intro at all: a person pasting a link
mid-conversation often does not preface it with anything, and always
prefacing one would just trade one repeated shape for another.
"""

LINKS_BY_CATEGORY = {
    "video": (
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/jNQXAC9IVRw",
        "https://www.youtube.com/watch?v=9bZkp7q19f0",
    ),
    "article": (
        "https://en.wikipedia.org/wiki/WebSocket",
        "https://en.wikipedia.org/wiki/Load_balancing_(computing)",
        "https://developer.mozilla.org/en-US/docs/Web/JavaScript",
        "https://en.wikipedia.org/wiki/Continuous_integration",
        "https://en.wikipedia.org/wiki/SQLite",
    ),
    "image": (
        "https://picsum.photos/seed/harbor/800/450",
        "https://picsum.photos/seed/forest/1200/630",
        "https://picsum.photos/seed/desk/600/400",
        "https://picsum.photos/seed/skyline/1000/500",
    ),
    "repo": (
        "https://github.com/flutter/flutter",
        "https://github.com/rust-lang/rust",
        "https://github.com/tokio-rs/tokio",
        "https://github.com/launchbadge/sqlx",
        "https://github.com/livekit/livekit",
    ),
}

# Flattened for callers (and tests) that only need "is this a real link".
LINKS = tuple(url for urls in LINKS_BY_CATEGORY.values() for url in urls)

_INTROS_BY_CATEGORY = {
    "video": ("worth a watch", "you have to see this", "check this out",
              "this had me cracking up"),
    "article": ("worth a read", "relevant", "found this earlier",
                "for reference"),
    "image": ("found this earlier", "look at this", "saw this today"),
    "repo": ("here's the repo", "linking this before I forget",
             "for reference", "found this earlier"),
}

# Share of link messages sent with no intro at all - just the bare URL.
_NO_INTRO_CHANCE = 0.3


def _category_of(url):
    """The category `url` was filed under; only ever called on a member of
    `LINKS`, so an unmatched url is this module's own bug, not bad input."""
    for category, urls in LINKS_BY_CATEGORY.items():
        if url in urls:
            return category
    raise KeyError(url)


def link_message(rng):
    """A URL, plus an intro drawn from that URL's own category most of the
    time - the shape a person actually pastes, sometimes with no preamble
    at all."""
    category = rng.choice(list(LINKS_BY_CATEGORY))
    url = rng.choice(LINKS_BY_CATEGORY[category])
    if rng.random() < _NO_INTRO_CHANCE:
        return url
    return f"{rng.choice(_INTROS_BY_CATEGORY[category])}: {url}"
