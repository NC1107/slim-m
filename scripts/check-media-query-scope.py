#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Guard against `MediaQuery.of(context)` drifting back into the client.

This codebase's own convention, set by `design_system`'s `sheet.dart` and
`menu.dart` and followed in 20+ `app` files, is the scoped accessors -
`MediaQuery.sizeOf(context)`, `MediaQuery.viewInsetsOf(context)`,
`MediaQuery.textScalerOf(context)`, and so on. `MediaQuery.of(context)`
subscribes the calling element to every field on `MediaQueryData` - text
scale, brightness, padding, orientation - so a widget that only cares about
the keyboard inset still rebuilds on a text-scale or brightness change.

A 2026-08 audit found a dozen keyboard-avoidance call sites that had been
copy-pasted with the unscoped form despite `threads_sheet.dart` using both
the correct and incorrect form roughly a hundred lines apart in the same
file - proof this is copy-paste drift, not a deliberate choice anywhere.
This gate reads each tracked `client/**/*.dart` file's own text rather than
keeping a list of what to check, the same reason `check-error-surface.py`
reads `catch` blocks straight out of source: a case this cannot see is a
case that was never written the wrong way in the first place.

Comments and string literals are stripped first (via `dart_source`, shared
with `check-error-surface.py`) so a doc comment that mentions
`MediaQuery.of(` in passing - this file's own module doc among them - can
never be misread as a call site.

`MEDIA_QUERY_OF_ALLOW` is a short, named allowlist for the rare call site
that genuinely needs the whole `MediaQueryData`, usually to `copyWith` one
field on top of the ambient value rather than read a single field of it.
See `scripts/media-query-of-allow.txt` for the current entries and why each
one is there.
"""

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))

from dart_source import strip_block_comments  # noqa: E402

ALLOWLIST_PATH = Path(__file__).resolve().parent / "media-query-of-allow.txt"
MEDIA_QUERY_OF = re.compile(r"MediaQuery\.of\(")


def load_allowlist(path: Path) -> set[str]:
    allowed: set[str] = set()
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        allowed.add(stripped.split("#", 1)[0].strip())
    return allowed


def main() -> int:
    root = Path(
        subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    )
    files = subprocess.run(
        ["git", "ls-files", "--", "client/*.dart", "client/**/*.dart"],
        capture_output=True, text=True, check=True, cwd=root,
    ).stdout.splitlines()
    if not files:
        print("::error::no files matched client/**/*.dart; the gate is not reading anything")
        return 1

    allowed = load_allowlist(ALLOWLIST_PATH)

    offenders: list[str] = []
    for rel in files:
        if rel in allowed:
            continue
        text = strip_block_comments((root / rel).read_text())
        for lineno, line in enumerate(text.splitlines(), start=1):
            if MEDIA_QUERY_OF.search(line):
                offenders.append(f"{rel}:{lineno}")

    for offender in offenders:
        path, _, lineno = offender.partition(":")
        print(
            f"::error file={path},line={lineno}::MediaQuery.of(context) subscribes to every "
            "MediaQueryData field; use the scoped accessor this call site actually needs "
            "(MediaQuery.sizeOf, MediaQuery.viewInsetsOf, MediaQuery.textScalerOf, ...), or "
            f"if the whole MediaQueryData is genuinely needed, add '{path} # why' to "
            "scripts/media-query-of-allow.txt"
        )

    print(f"MediaQuery.of: {len(files)} file(s) checked, {len(allowed)} allowlisted, {len(offenders)} offender(s)")
    return 1 if offenders else 0


if __name__ == "__main__":
    sys.exit(main())
