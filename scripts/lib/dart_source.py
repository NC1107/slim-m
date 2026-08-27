# SPDX-License-Identifier: Apache-2.0
"""Shared text-scrubbing for source-reading hygiene gates over `.dart` files.

Extracted out of `scripts/check-error-surface.py`, which was the first gate
to need this: a raw substring or brace-counting scan over Dart source is
fooled by a comment or string literal that happens to contain the exact
shape being searched for. Any new source-reading gate over Dart files should
import `strip_block_comments` from here rather than writing its own scanner,
per this project's own rule that a source-reading gate must strip comments
and strings before matching.
"""


def strip_block_comments(text: str) -> str:
    """Blanks `//` and `/* ... */` comment text to spaces, keeping every
    line and column where it was so line numbers downstream stay accurate.

    String-aware: a `//`, `/*` or `*/` inside a `'...'` or `"..."` literal is
    left alone rather than misread as a comment boundary, which would blank
    real code sitting between two such string literals.

    Line comments are blanked, not just skipped, so a gate built on this
    cannot be fooled by a doc comment that happens to mention the exact
    code shape it is searching for.
    """
    out: list[str] = []
    i, n = 0, len(text)
    quote: str | None = None
    while i < n:
        c = text[i]
        if quote:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 2
                continue
            if c == quote:
                quote = None
            i += 1
            continue
        if c in "'\"":
            quote = c
            out.append(c)
            i += 1
            continue
        if text[i : i + 2] == "//":
            end = text.find("\n", i)
            end = n if end == -1 else end
            out.append(" " * (end - i))
            i = end
            continue
        if text[i : i + 2] == "/*":
            end = text.find("*/", i + 2)
            end = n if end == -1 else end + 2
            out.append("".join("\n" if ch == "\n" else " " for ch in text[i:end]))
            i = end
            continue
        out.append(c)
        i += 1
    return "".join(out)
