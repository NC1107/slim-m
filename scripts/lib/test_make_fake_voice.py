# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""The fake microphone has to be audio a voice-activity detector believes.

Chrome's own fake tone is not: a real e2e run reached the call with both
participant tiles on screen, correctly named, and neither ever flagged as
speaking. So the thing this generator produces is the whole point of the
`voice: audio actually arrives` scenario, and these are the properties that
make it work rather than the shape of the code that makes it.

Cheap to check and expensive to get wrong silently, since the failure mode is
a voice test that passes for the wrong reason or fails for no visible one.
"""
import math
import struct
import sys
import tempfile
import unittest
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import make_fake_voice as m  # noqa: E402


class FakeVoiceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._dir = tempfile.TemporaryDirectory()
        cls.path = Path(cls._dir.name) / "voice.wav"
        m.write(str(cls.path))
        with wave.open(str(cls.path)) as w:
            cls.channels = w.getnchannels()
            cls.rate = w.getframerate()
            cls.width = w.getsampwidth()
            frames = w.readframes(w.getnframes())
        cls.samples = struct.unpack(f"<{len(frames) // 2}h", frames)

    @classmethod
    def tearDownClass(cls):
        cls._dir.cleanup()

    def test_it_is_the_format_chrome_requires(self):
        """16-bit PCM mono; Chrome refuses the flag's file otherwise."""
        self.assertEqual((self.channels, self.width), (1, 2))
        self.assertEqual(self.rate, 48_000)

    def test_it_is_loud_enough_to_clear_a_threshold(self):
        rms = math.sqrt(sum(s * s for s in self.samples) / len(self.samples))
        self.assertGreater(
            rms / 32767, 0.05,
            "quieter than about -26 dBFS is what left the last run silent")

    def test_it_never_clips(self):
        """A clipped signal is distortion, which a detector may discard."""
        self.assertLessEqual(max(abs(s) for s in self.samples), 32767)

    def test_it_has_gaps_like_speech_rather_than_a_steady_tone(self):
        """Voice-activity detection is built to ignore a continuous tone."""
        silent = sum(1 for s in self.samples if s == 0) / len(self.samples)
        self.assertGreater(silent, 0.1, "no syllable gaps at all")
        self.assertLess(silent, 0.6, "more gap than sound")

    def test_it_is_long_enough_to_loop_without_a_seam_every_moment(self):
        seconds = len(self.samples) / self.rate
        self.assertGreaterEqual(seconds, 2)

    def test_it_starts_and_ends_quiet_so_the_loop_does_not_click(self):
        """Quiet, not digitally silent: a hard edge is the click, and the
        envelope's own first sample is a handful of counts above zero."""
        edge = 200
        floor = 0.01 * 32767
        self.assertLess(max(abs(s) for s in self.samples[:edge]), floor)
        self.assertLess(max(abs(s) for s in self.samples[-edge:]), floor)


if __name__ == "__main__":
    unittest.main()
