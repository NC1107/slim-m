# SPDX-License-Identifier: Apache-2.0
"""What has to stay true of the notification sounds.

The first of these is the one that matters and the one that was missing: a
family normalised to a target is not the same thing as a family that is level
with itself, and the first build of this set passed every per-file check while
spanning 3.4 dB. Nothing noticed, because nothing had ever compared the seven
on one scale.

Run with: python3 -m unittest discover -s assets/audio
"""
from __future__ import annotations

import subprocess
import sys
import unittest
import wave
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "notifications"))

import synth  # noqa: E402
from sounds import SOUNDS  # noqa: E402

OUT = HERE / "notifications"


def read(path: Path) -> np.ndarray:
    with wave.open(str(path)) as w:
        assert w.getnchannels() == 1, f"{path.name} is not mono"
        assert w.getsampwidth() == 2, f"{path.name} is not 16-bit"
        assert w.getframerate() == synth.SAMPLE_RATE, f"{path.name} rate"
        raw = w.readframes(w.getnframes())
    return np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32767.0


def _max_flat_rms_db(signal: np.ndarray) -> float:
    """The loudest 200ms window's RMS in dB, with no weighting filter at all.

    Independent of `synth.loudness` on purpose: it shares none of the
    K-weighting code, so it can contradict a filter bug that measure cannot
    see in itself.
    """
    window = int(0.2 * synth.SAMPLE_RATE)
    squared = signal.astype(np.float64) ** 2
    if squared.size <= window:
        return 10.0 * np.log10(float(np.mean(squared)))
    cumulative = np.concatenate([[0.0], np.cumsum(squared)])
    sums = cumulative[window:] - cumulative[:-window]
    return 10.0 * np.log10(float(np.max(sums)) / window)


class SoundFamily(unittest.TestCase):
    def setUp(self) -> None:
        self.clips = {name: read(OUT / f"{name}.wav") for name in SOUNDS}

    def test_every_sound_exists(self) -> None:
        self.assertEqual(len(self.clips), 7, "the family is seven sounds")

    def test_the_family_is_level_with_itself(self) -> None:
        """The normaliser converged: every clip is at the target it aimed for.

        Measured with `synth.loudness`, which is also what `normalise` uses to
        set the level, so this proves the normaliser ran and converged (it
        catches a no-op normaliser) but not that `loudness` measures the right
        thing. The independent check below is what covers that.
        """
        levels = {n: synth.loudness(x) for n, x in self.clips.items()}
        spread = max(levels.values()) - min(levels.values())
        self.assertLess(
            spread, 0.5,
            f"the family spans {spread:.2f} dB by its own meter: {levels}")

    def test_the_family_is_level_by_an_independent_measure(self) -> None:
        """Level by a measure that never touches the K-weighting filter.

        The test above uses the same function that set the levels, so a bug in
        the K-weighting biquad in `synth.loudness` would make a de-levelled
        family pass it. Flat RMS over the loudest short window shares none of
        that code: if the filter were wrong in a way that hid a real spread,
        the two measures would disagree. Looser than the band above because
        K-weighting deliberately shapes the spectrum, but a shared timbre keeps
        the flat and weighted levels close, and 1.5 dB catches a real drift.
        """
        levels = {n: _max_flat_rms_db(x) for n, x in self.clips.items()}
        spread = max(levels.values()) - min(levels.values())
        self.assertLess(
            spread, 1.5,
            f"flat-RMS spread is {spread:.2f} dB: {levels}")

    def test_no_sound_is_peaky_in_a_way_loudness_missed(self) -> None:
        """An independent check, because the one above is the target itself.

        Peak is not what normalised these, so a sound whose crest factor is
        wildly unlike the rest would show here even though its measured
        loudness matched. That is the shape of sound that reads as a click.

        BS.1770 was the first cross-check tried and is not usable at these
        lengths: every clip is one to three gate blocks, and padding one to
        make gating possible dilutes it by 3 dB, which says something about
        the measurement rather than about the sound.
        """
        peaks = {n: 20.0 * np.log10(float(np.abs(x).max()))
                 for n, x in self.clips.items()}
        spread = max(peaks.values()) - min(peaks.values())
        self.assertLess(
            spread, 4.0,
            f"peak spread is {spread:.2f} dB: {peaks}")

    def test_nothing_clips(self) -> None:
        for name, clip in self.clips.items():
            with self.subTest(name):
                self.assertLess(float(np.abs(clip).max()), 1.0)

    def test_no_two_sounds_are_the_same(self) -> None:
        """Seven sounds a person has to tell apart, so seven waveforms."""
        seen: dict[bytes, str] = {}
        for name, clip in self.clips.items():
            key = clip.tobytes()
            self.assertNotIn(key, seen, f"{name} is identical to {seen.get(key)}")
            seen[key] = name

    def test_join_rises_and_leave_falls(self) -> None:
        """The pair is mirrored, which is what makes it learnable.

        Compared by where the energy sits early against late, rather than by
        reading the note list back, which would only prove the test can read
        the same file the generator wrote.
        """
        for name, expect_rising in (("member_join", True),
                                    ("member_leave", False)):
            with self.subTest(name):
                clip = self.clips[name]
                third = clip.size // 3
                early = np.fft.rfft(clip[:third])
                late = np.fft.rfft(clip[-third:])
                freqs = np.fft.rfftfreq(third, 1 / synth.SAMPLE_RATE)
                early_hz = float(freqs[np.argmax(np.abs(early))])
                late_hz = float(freqs[np.argmax(np.abs(late))])
                if expect_rising:
                    self.assertGreater(late_hz, early_hz)
                else:
                    self.assertLess(late_hz, early_hz)

    def test_regenerating_changes_nothing(self) -> None:
        """The committed WAVs are what this code makes, or the gate is a lie."""
        before = {p.name: p.read_bytes() for p in OUT.glob("*.wav")}
        subprocess.run(
            [sys.executable, str(HERE / "generate.py")],
            check=True, capture_output=True)
        after = {p.name: p.read_bytes() for p in OUT.glob("*.wav")}
        self.assertEqual(
            sorted(before), sorted(after), "a sound appeared or vanished")
        drifted = [n for n in before if before[n] != after[n]]
        self.assertEqual(drifted, [], f"regenerating changed {drifted}")


if __name__ == "__main__":
    unittest.main()
