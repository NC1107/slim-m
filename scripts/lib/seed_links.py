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
"""

_INTROS = (
    "check this out", "found this earlier", "relevant", "worth a watch",
    "here's the repo", "saw this today", "thought you'd like this",
    "for reference", "linking this before I forget", "related",
)

LINKS = (
    "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
    "https://youtu.be/jNQXAC9IVRw",
    "https://www.youtube.com/watch?v=9bZkp7q19f0",
    "https://en.wikipedia.org/wiki/WebSocket",
    "https://en.wikipedia.org/wiki/Load_balancing_(computing)",
    "https://developer.mozilla.org/en-US/docs/Web/JavaScript",
    "https://en.wikipedia.org/wiki/Continuous_integration",
    "https://en.wikipedia.org/wiki/SQLite",
    "https://picsum.photos/seed/harbor/800/450",
    "https://picsum.photos/seed/forest/1200/630",
    "https://picsum.photos/seed/desk/600/400",
    "https://picsum.photos/seed/skyline/1000/500",
    "https://github.com/flutter/flutter",
    "https://github.com/rust-lang/rust",
    "https://github.com/tokio-rs/tokio",
    "https://github.com/launchbadge/sqlx",
    "https://github.com/livekit/livekit",
)


def link_message(rng):
    """A short intro plus one URL - the shape a person actually pastes."""
    return f"{rng.choice(_INTROS)}: {rng.choice(LINKS)}"
