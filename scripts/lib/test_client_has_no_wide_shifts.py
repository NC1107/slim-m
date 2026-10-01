# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""No client Dart shifts an int by 32 bits or more.

Compiled to JavaScript such a shift is zero, and the VM test run cannot see
it: it broke the canvas z-index, web message ids and the canvas cell key.
"""
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from dart_source import strip_block_comments  # noqa: E402

PACKAGES = Path(__file__).resolve().parents[2] / "client" / "packages"
WIDE_SHIFT = re.compile(r"(?:<<|>>>?)\s*(\d+)")
STRING = re.compile(r"'(?:\\.|[^'\\\n])*'|\"(?:\\.|[^\"\\\n])*\"")


def wide_shifts(source: str) -> list[int]:
    """The 1-based lines of `source` that shift by a literal of 32 or more."""
    code = STRING.sub("''", strip_block_comments(source))
    return [
        code.count("\n", 0, match.start()) + 1
        for match in WIDE_SHIFT.finditer(code)
        if int(match.group(1)) >= 32
    ]


class ClientHasNoWideShiftsTest(unittest.TestCase):
    def test_no_lib_file_shifts_past_thirty_one_bits(self):
        found = []
        for path in sorted(PACKAGES.glob("*/lib/**/*.dart")):
            if path.name.endswith(".g.dart"):
                continue
            for line in wide_shifts(path.read_text()):
                found.append(f"{path.relative_to(PACKAGES)}:{line}")
        self.assertGreater(len(list(PACKAGES.glob("*/lib/**/*.dart"))), 100)
        self.assertEqual(found, [])

    def test_the_shapes_that_shipped_are_caught(self):
        self.assertEqual(wide_shifts("final a = (now >> 40) & 0xff;\n"), [1])
        self.assertEqual(wide_shifts("x =\n  (cx & 0xffffffff) << 32 | cy;\n"), [2])

    def test_narrow_shifts_comments_and_strings_are_not(self):
        self.assertEqual(wide_shifts("final a = (now >> 24) & 0xff;\n"), [])
        self.assertEqual(wide_shifts("// rather than `1 << 40`\n"), [])
        self.assertEqual(wide_shifts("/// a doc about x << 32\nfinal s = 'a >> 40';\n"), [])


if __name__ == "__main__":
    unittest.main()
