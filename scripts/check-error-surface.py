#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""A failure caught from the server is a SnackBar again, three times over.

The nine-specialist audit (2026-07-29) replaced 27 vanishing SnackBars with
persistent `AppErrorState`, on the grounds that a failure which disappears on
its own is a failure nobody saw. A later copy pass found three of them back:
the channel overwrites screen, avatar upload and removal, and the blocked-row
unblock, each caught its own `ApiException` and showed it with a SnackBar
sitting beside a sibling row doing it properly. Nothing gated that; this does.

The distinction is not "is there a SnackBar", which `run_guarded.dart`'s own
doc comment already draws: a surface that has already closed by the time its
request answers (a popover dismissed on tap) has nowhere to put an inline
state, and a SnackBar is genuinely the only option left. Every such call site
in this codebase reaches it through `runGuarded`'s returned sentence, never by
catching `ApiException` itself - so the shape this gate looks for is narrower
and sharper than "any SnackBar near a failure": a widget that catches an API
exception directly and hands the message to `ScaffoldMessenger`/`SnackBar`
rather than to `GuardedActionState`/`AppErrorState`, the two `run_guarded.dart`
actually offers for that failure. That is exactly the shape the three
regressions had, and exactly the shape every fixed site does not.

Reads the `on api.<Something>Exception` blocks straight out of each `.dart`
file's own text rather than keeping a list of what to check: a case this
cannot see is a case that was never written the wrong way in the first
place, so there is nothing to fall out of date.

The `catch (e)` clause is optional in the pattern on purpose: `on
api.ApiException { ... }` with no bound variable is valid Dart, and an
earlier version of this regex required the literal word `catch`, so that
exact shape - unreachable to the interpolation risk `describeApiFailure`
guards against, but just as reachable to a raw `ScaffoldMessenger` call -
sailed through unseen. `presence_controller.dart` alone already has one;
none of them show a SnackBar today, so nothing here was retroactively wrong,
only the gate meant to keep it that way.

`EXCEPTIONS` below is a short, named allowlist rather than a growing file, the
same discipline `type_scale_literal_test.dart` already holds everyone else to:
each entry carries its own one-line why, right beside it. It starts empty,
deliberately - every legitimate SnackBar in this codebase already routes
around a raw catch entirely, through `runGuarded`'s own returned sentence, so
there was no real case to seed it with. Add an entry only for a genuinely new
case of the same shape a popover already gets away with: a surface gone by the
time the request answers, never to silence an actual regression.

A bare `catch (e) { ... }` is checked too, added when three file-picker-open
failures (the emoji upload card, the avatar section, the composer) turned out
to carry this exact shape on a bare catch rather than `on api.*Exception`: a
native picker throwing is not an `ApiException` at all, so the narrower
pattern above could never have seen it. The two patterns cannot overlap - `on
Type catch (e) {` never starts with the literal word `catch`, since `on Type`
sits before it - so this is strictly a wider net, not a replacement.

`SHOWS_SNACKBAR` had never matched a single real call in this codebase: every
site (including the three above) calls `showAppSnackbar`, not the raw
`ScaffoldMessenger`/`SnackBar(` this pattern watched for, so the gate reported
zero offenders whether or not one existed - confirmed by mutating a fixed site
back to its old shape and finding the gate said nothing. `showAppSnackbar` is
now in the pattern too; the two raw shapes stay in it for whatever still
calls them directly, `personal_space_menu.dart`'s success-notice path among
them, which is not itself in scope since it sits outside any catch block.

Not caught, and not a defect in the fix: `composer.dart`'s own picker failure
runs through `attachment_picker.dart`'s shared `runAttachmentPick`, whose
catch block calls back a plain `onPickerFailed()` parameter rather than
naming `showAppSnackbar` in its own body - the call is one file away, at the
composer's own call site. A regex reading one function at a time cannot see
across that indirection; `composer_affordances_test.dart`'s own regression
test is what actually guards that site, mutation-tested the same way.
"""

import re
import subprocess
import sys
from pathlib import Path

EXCEPTIONS: dict[tuple[str, int], str] = {}

CATCH_HEADER = re.compile(
    r"^(?P<indent>[ \t]*)(?:\}[ \t]*)?on[ \t]+api\.\w*Exception"
    r"(?:[ \t]+catch\b[^{]*)?[ \t]*\{[ \t]*$"
)
BARE_CATCH_HEADER = re.compile(
    r"^(?P<indent>[ \t]*)(?:\}[ \t]*)?catch[ \t]*\([^)]*\)[ \t]*\{[ \t]*$"
)
SHOWS_SNACKBAR = re.compile(r"ScaffoldMessenger|SnackBar\(|showAppSnackbar\(")


def catch_blocks(lines: list[str]):
    """Yields (1-based header line, body lines) for each caught-exception block.

    Either an `on api.*Exception catch { ... }` or a bare `catch (e) { ... }`
    header; see this file's own module doc for why both are in scope. The
    block's end is the next line, at the header's indentation or less, that
    opens with `}` - the same section-by-indentation technique `hygiene.yml`'s
    own `section()` helper already uses for a Dart brace this project has no
    AST tool handy for in a plain hygiene step.
    """
    for i, line in enumerate(lines):
        header = CATCH_HEADER.match(line) or BARE_CATCH_HEADER.match(line)
        if not header:
            continue
        indent = header.group("indent")
        body: list[str] = []
        j = i + 1
        while j < len(lines):
            candidate = lines[j]
            stripped = candidate.lstrip()
            current_indent = candidate[: len(candidate) - len(stripped)]
            if stripped.startswith("}") and len(current_indent) <= len(indent):
                break
            body.append(candidate)
            j += 1
        yield i + 1, body


def main() -> int:
    root = Path(
        subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    )
    files = subprocess.run(
        ["git", "ls-files", "--", "client/packages/app/lib/*.dart"],
        capture_output=True, text=True, check=True, cwd=root,
    ).stdout.splitlines()
    if not files:
        print("::error::no files matched client/packages/app/lib/*.dart; the gate is not reading anything")
        return 1

    checked = 0
    offenders: list[str] = []
    for rel in files:
        lines = (root / rel).read_text().splitlines()
        for lineno, body in catch_blocks(lines):
            checked += 1
            if not any(SHOWS_SNACKBAR.search(candidate) for candidate in body):
                continue
            if (rel, lineno) in EXCEPTIONS:
                continue
            offenders.append(f"{rel}:{lineno}")

    if checked == 0:
        print("::error::no caught-exception blocks found anywhere; the gate is not reading anything")
        return 1

    for offender in offenders:
        path, _, lineno = offender.partition(":")
        entry = f'("{path}", {lineno}): "why",'
        print(
            f"::error file={path},line={lineno}::a caught failure is shown with a "
            "SnackBar here; use GuardedActionState/AppErrorState instead (see "
            "run_guarded.dart's own doc comment), or if this surface has "
            "genuinely already closed by the time the request answers, add "
            f"'{entry}' to EXCEPTIONS in scripts/check-error-surface.py"
        )

    print(f"error surface: {checked} catch block(s) checked in {len(files)} files, {len(offenders)} offender(s)")
    return 1 if offenders else 0


if __name__ == "__main__":
    sys.exit(main())
