# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Every decision record is in the README index exactly once, under its own number.

The index is written by hand. On 2026-10-01 two branches both claimed 0053, and a
record kept a 0053 title after it was renumbered to 0055. Nothing noticed either,
so this checks the files against the index and each file against its own heading.
"""

import re
import tempfile
import unittest
from pathlib import Path

DECISIONS = Path(__file__).resolve().parents[2] / "docs" / "decisions"
RECORD = re.compile(r"^(\d{4})-.+\.md$")
ROW = re.compile(r"^\| \[(\d{4})\]\(([^)]+)\) \|")
HEADING = re.compile(r"^# (\d{4}) - ")


def problems(directory: Path) -> list[str]:
    found: list[str] = []
    files = sorted(p.name for p in directory.iterdir() if RECORD.match(p.name))
    by_number: dict[str, list[str]] = {}
    for name in files:
        by_number.setdefault(name[:4], []).append(name)
    for number, names in by_number.items():
        if len(names) > 1:
            found.append(f"number {number} is used by {names}")

    indexed: dict[str, str] = {}
    for line in (directory / "README.md").read_text().splitlines():
        row = ROW.match(line)
        if not row:
            continue
        number, target = row.groups()
        if not (directory / target).is_file():
            found.append(f"row {number} links {target}, which does not exist")
        elif target[:4] != number:
            found.append(f"row {number} links {target}, which has another number")
        if target in indexed:
            found.append(f"{target} has two rows")
        indexed[target] = number
    for name in files:
        if name not in indexed:
            found.append(f"{name} has no row in README.md")

    for name in files:
        first = next(
            (l for l in (directory / name).read_text().splitlines() if l.startswith("# ")),
            "",
        )
        heading = HEADING.match(first)
        if not heading or heading.group(1) != name[:4]:
            found.append(f"{name} first heading must start '# {name[:4]} - ': {first!r}")
    return found


def build(files: dict[str, str], rows: list[tuple[str, str]]) -> Path:
    root = Path(tempfile.mkdtemp(prefix="decision-index-"))
    for name, text in files.items():
        (root / name).write_text(text)
    table = "".join(f"| [{n}]({t}) | title | accepted |\n" for n, t in rows)
    (root / "README.md").write_text("| Record | Title | Status |\n| --- | --- | --- |\n" + table)
    return root


class DecisionIndexTest(unittest.TestCase):
    def test_the_real_index_is_consistent(self):
        self.assertEqual(problems(DECISIONS), [])

    def test_a_consistent_index_passes(self):
        root = build({"0001-a.md": "# 0001 - a\n"}, [("0001", "0001-a.md")])
        self.assertEqual(problems(root), [])

    def test_a_record_without_a_row_fails(self):
        root = build({"0001-a.md": "# 0001 - a\n", "0002-b.md": "# 0002 - b\n"}, [("0001", "0001-a.md")])
        self.assertEqual(problems(root), ["0002-b.md has no row in README.md"])

    def test_a_shared_number_fails(self):
        root = build(
            {"0003-a.md": "# 0003 - a\n", "0003-b.md": "# 0003 - b\n"},
            [("0003", "0003-a.md"), ("0003", "0003-b.md")],
        )
        self.assertEqual(problems(root), ["number 0003 is used by ['0003-a.md', '0003-b.md']"])

    def test_a_row_linking_a_missing_file_fails(self):
        root = build({"0001-a.md": "# 0001 - a\n"}, [("0001", "0001-a.md"), ("0002", "0002-gone.md")])
        self.assertEqual(problems(root), ["row 0002 links 0002-gone.md, which does not exist"])

    def test_a_row_number_that_differs_from_its_file_fails(self):
        root = build({"0001-a.md": "# 0001 - a\n"}, [("0009", "0001-a.md")])
        self.assertEqual(problems(root), ["row 0009 links 0001-a.md, which has another number"])

    def test_a_heading_with_another_number_fails(self):
        root = build({"0055-a.md": "# 0053 - a\n"}, [("0055", "0055-a.md")])
        self.assertEqual(len(problems(root)), 1)
        self.assertIn("first heading must start '# 0055 - '", problems(root)[0])


if __name__ == "__main__":
    unittest.main()
