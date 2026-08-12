#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Every object in an Xcode project file must have its own id.

An `.xcodeproj` is a flat map from 24-hex-digit id to object, and the sections
it is written in are presentation only - a build phase referring to an id gets
whatever object that id names, whatever section it was defined in. So reusing
an id that is already a target, a group or a build-configuration list does not
shadow it or fail to resolve: it makes one id mean two things, and Xcode
resolves references to whichever it happens to hold.

The symptom is not a parse error naming the line. Xcode reports the whole
project as "damaged and cannot be opened", with an `unrecognized selector`
naming the two types that got confused and nothing naming the id or the file.
That is a hard failure of `xcodebuild`, so it costs a full macOS runner to
find out, and every job needing the project fails at once with the same
uninformative message.

This is a text check with no Xcode in it, which is why it can run on ubuntu
ahead of the macOS jobs and answer in a second. It reads an object definition
as an id at the head of a line followed by an opening brace, deliberately
without matching the /* comment */ many of them carry: that buys nothing here
and costs a lazy quantifier over attacker-irrelevant but needlessly
backtracking input.
"""

import re
import sys

# Only at the head of a line; a reference to an id always sits after a key.
OPENING = re.compile(r"^[ \t]*([0-9A-F]{24})\b")

# What follows the id when it introduces an object rather than naming one.
OPENS = "= {"

# What every real object carries and nothing else does.
ISA = "isa = "


def opens_an_object(lines, index):
    """Whether the brace opened at [index] is an object rather than a key.

    The project section keys `TargetAttributes` by target id, which looks
    exactly like a definition and is not one - checking for `isa` is what
    tells a real object from a dictionary that happens to be keyed by an id.
    A one-line object carries it inline; a multi-line one carries it on the
    next line.
    """
    if ISA in lines[index]:
        return True
    following = index + 1
    return following < len(lines) and ISA in lines[following]


def duplicate_ids(text):
    """Ids defined more than once, each with the lines that defined them."""
    lines = text.splitlines()
    seen = {}
    for index, line in enumerate(lines):
        match = OPENING.match(line)
        if match and OPENS in line and opens_an_object(lines, index):
            seen.setdefault(match.group(1), []).append((index + 1, line.strip()))
    return {key: found for key, found in seen.items() if len(found) > 1}


def main(paths):
    failed = False
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            duplicates = duplicate_ids(handle.read())
        for object_id, lines in sorted(duplicates.items()):
            failed = True
            first = lines[0][0]
            print(
                f"::error file={path},line={first}::{object_id} defines "
                f"{len(lines)} different objects; every id must be unique"
            )
            for number, line in lines:
                print(f"  {path}:{number}: {line}")
    if not failed:
        print(f"pbxproj ids: {len(paths)} file(s) checked, every id unique")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
