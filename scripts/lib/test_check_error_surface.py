# SPDX-License-Identifier: Apache-2.0
"""Unit coverage for scripts/check-error-surface.py.

Drives the real script against a real temp git repo, the same technique
test_check_release_tag_lag.py already uses, because the thing under test
reads `git ls-files` and a file's own text rather than anything a stub
could fake convincingly.

The regression this exists for: an adversarial pass found that `on
api.ApiException { ... }` - valid Dart, catching by type with no bound
variable - was invisible to the gate's original regex, which hard-required
the literal word `catch`. That shape already exists unremarkably several
times in this codebase (presence_controller.dart, blocks_controller.dart,
and others all silently swallow a failure this way), so the blind spot was
not hypothetical: a `ScaffoldMessenger` call dropped into any one of them
would have shipped past this gate exactly the way the three regressions
this gate exists to catch once did.
"""
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "check-error-surface.py"


class CheckErrorSurfaceTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.repo = Path(self._tmp.name)
        self._git("init", "-q")
        self._git("config", "user.email", "test@example.invalid")
        self._git("config", "user.name", "test")
        self.lib = self.repo / "client" / "packages" / "app" / "lib"
        self.lib.mkdir(parents=True)

    def _git(self, *args):
        subprocess.run(
            ["git", *args], cwd=self.repo, check=True,
            capture_output=True, text=True)

    def _write(self, name, body):
        path = self.lib / name
        path.write_text(body)
        self._git("add", str(path.relative_to(self.repo)))

    def _run(self):
        return subprocess.run(
            [sys.executable, str(SCRIPT)], cwd=self.repo,
            capture_output=True, text=True)

    def test_a_guarded_catch_with_no_snackbar_is_fine(self):
        self._write("ok.dart", """
class Foo {
  Future<void> go() async {
    try {
      await api.thing();
    } on api.ApiException catch (e) {
      setState(() => _error = describeApiFailure('do the thing', e));
    }
  }
}
""")
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("0 offender(s)", result.stdout)

    def test_a_bound_catch_showing_a_snackbar_is_still_caught(self):
        """The original three regressions this gate was built for."""
        self._write("bad_bound.dart", """
class Foo {
  Future<void> go() async {
    try {
      await api.thing();
    } on api.ApiException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
""")
        result = self._run()
        self.assertEqual(result.returncode, 1)
        self.assertIn("file=client/packages/app/lib/bad_bound.dart,line=6",
                       result.stdout + result.stderr)

    def test_an_unbound_catch_showing_a_snackbar_is_caught(self):
        """`on api.ApiException { ... }`, no `catch (e)` at all - valid
        Dart, and the exact shape the original regex could not see."""
        self._write("bad_unbound.dart", """
class Foo {
  Future<void> go() async {
    try {
      await api.thing();
    } on api.ApiException {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed.')));
    }
  }
}
""")
        result = self._run()
        self.assertEqual(result.returncode, 1)
        self.assertIn("file=client/packages/app/lib/bad_unbound.dart,line=6",
                       result.stdout + result.stderr)

    def test_an_unbound_catch_that_swallows_silently_is_fine(self):
        """The common, correct shape: nothing to show, nothing shown."""
        self._write("ok_unbound.dart", """
class Foo {
  Future<void> go() async {
    try {
      await api.thing();
    } on api.ApiException {
      // nothing useful to do
    }
  }
}
""")
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("0 offender(s)", result.stdout)

    def test_a_catcherror_callback_showing_a_snackbar_is_caught(self):
        """A Future's own `.catchError((e) { ... })`, not a `catch` block at
        all - reproduced by an adversarial pass, which found the gate said
        nothing while this exact shape sat in a tracked file."""
        self._write("bad_catcherror.dart", """
class Foo {
  void go() {
    api.thing().catchError((e) {
      showAppSnackbar(context, e.toString());
    });
  }
}
""")
        result = self._run()
        self.assertEqual(result.returncode, 1)
        self.assertIn(
            "file=client/packages/app/lib/bad_catcherror.dart,line=4",
            result.stdout + result.stderr)

    def test_a_catcherror_callback_that_swallows_silently_is_fine(self):
        """The idiom this codebase already uses elsewhere
        (sync_controller.dart, providers.dart) to drop a failure on the
        floor on purpose - must not become an offender just for existing.
        Multi-line on purpose: a one-line `.catchError((_) {});` closes on
        the header's own line and is never recognised as a block at all,
        which would make this test pass for the wrong reason."""
        self._write("ok_catcherror.dart", """
class Foo {
  void go() {
    api.thing().catchError((_) {
      // nothing useful to do
    });
  }
}
""")
        result = self._run()
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("0 offender(s)", result.stdout)


if __name__ == "__main__":
    unittest.main()
