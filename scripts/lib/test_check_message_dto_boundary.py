# SPDX-License-Identifier: Apache-2.0
"""Unit coverage for scripts/check-message-dto-boundary.py.

Drives the real script against a real temp git repo, the same technique
test_check_error_surface.py already uses: the script itself resolves its
root with `git rev-parse --show-toplevel`, so a synthetic repo is what lets
these tests exercise it without touching the real `data.dart`.
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "check-message-dto-boundary.py"


class CheckMessageDtoBoundaryTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.repo = Path(self._tmp.name)
        self._git("init", "-q")
        self._git("config", "user.email", "test@example.invalid")
        self._git("config", "user.name", "test")
        self.lib = self.repo / "client" / "packages" / "data" / "lib"
        (self.lib / "src").mkdir(parents=True)

    def _git(self, *args):
        subprocess.run(
            ["git", *args], cwd=self.repo, check=True,
            capture_output=True, text=True)

    def _write(self, rel, body):
        path = self.lib / rel
        path.write_text(body)
        self._git("add", str(path.relative_to(self.repo)))

    def _run(self):
        return subprocess.run(
            [sys.executable, str(SCRIPT)], cwd=self.repo,
            capture_output=True, text=True)

    def test_a_plain_dto_export_passes(self):
        self._write("data.dart", """
export 'src/database.dart' show SlimmDatabase, Channel;
export 'src/message_dto.dart' show Message;
""")
        self._write("src/message_dto.dart", """
class Message {
  const Message({required this.id});
  final String id;
}
""")
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("message DTO boundary ok", result.stdout)

    def test_re_exporting_the_drift_row_fails(self):
        """The exact regression this gate exists for: `Message` pointed
        back at the drift-generated table file instead of the plain DTO."""
        self._write("data.dart", """
export 'src/database.dart' show SlimmDatabase, Channel, Message;
""")
        self._write("src/database.dart", """
import 'package:drift/drift.dart';

class Message extends DataClass implements Insertable<Message> {
  const Message({required this.id});
  final String id;
}
""")
        result = self._run()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("drift-coupled", result.stdout)

    def test_a_value_wrapper_leaking_through_the_dto_fails(self):
        """Not just a `DataClass`/`Insertable` re-export: a DTO that merely
        carries a drift `Value<T>` field in its own signature is caught too,
        per this project's own warning that a companion or wrapper type can
        leak through a boundary type that otherwise looks plain."""
        self._write("data.dart", """
export 'src/message_dto.dart' show Message;
""")
        self._write("src/message_dto.dart", """
import 'package:drift/drift.dart';

class Message {
  const Message({required this.id});
  final Value<String> id;
}
""")
        result = self._run()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("drift-coupled", result.stdout)

    def test_no_message_export_at_all_fails(self):
        self._write("data.dart", """
export 'src/database.dart' show SlimmDatabase, Channel;
""")
        self._write("src/database.dart", "class Channel {}\n")
        result = self._run()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("no export shows a Message", result.stdout)

    def test_missing_data_dart_fails(self):
        result = self._run()
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("expected file not found", result.stdout)


if __name__ == "__main__":
    unittest.main()
