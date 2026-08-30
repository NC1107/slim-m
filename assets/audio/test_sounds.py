# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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
from sounds import CALLKIT_RINGTONE, SOUNDS  # noqa: E402

OUT = HERE / "notifications"

# Apple's own ceiling; past this CallKit silently plays the default ringtone.
CALLKIT_RINGTONE_MAX_SECONDS = 30.0


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


class CallKitRingtone(unittest.TestCase):
    """The CallKit ringtone, checked against Apple's own constraints.

    Not a SoundFamily member and not compared against the seven on purpose:
    it is a system asset for CXProviderConfiguration.ringtoneSound rather
    than an in-app chime, so the family's cross-sound loudness invariants do
    not apply to it, and it is exempt from `test_every_sound_exists`'s count.
    """

    def setUp(self) -> None:
        self.clip = read(OUT / "callkit_ringtone.wav")

    def test_is_not_one_of_the_seven(self) -> None:
        self.assertNotIn("callkit_ringtone", SOUNDS)

    def test_within_callkits_own_length_ceiling(self) -> None:
        seconds = self.clip.size / synth.SAMPLE_RATE
        self.assertLess(
            seconds, CALLKIT_RINGTONE_MAX_SECONDS,
            "past this, CallKit silently plays the default ringtone instead")

    def test_matches_its_own_declared_notes(self) -> None:
        notes, _ = CALLKIT_RINGTONE
        rendered = synth.normalise(synth.render(notes))
        expected = np.round(np.clip(rendered, -1.0, 1.0) * 32767.0) / 32767.0
        actual = np.round(self.clip * 32767.0) / 32767.0
        self.assertTrue(
            np.array_equal(expected, actual),
            "the committed wav does not match sounds.py's own CALLKIT_RINGTONE")

    def test_nothing_clips(self) -> None:
        self.assertLess(float(np.abs(self.clip).max()), 1.0)

    def test_ring_and_pause_alternate(self) -> None:
        """A real cadence, not one continuous tone.

        Checked as energy over time rather than by re-reading the note list,
        which would only prove this test can read the same file the
        generator wrote.
        """
        window = int(0.05 * synth.SAMPLE_RATE)
        energy = np.array([
            float(np.mean(self.clip[i:i + window] ** 2))
            for i in range(0, self.clip.size - window, window)
        ])
        loud = energy > (energy.max() * 0.05)
        # A silent window between two loud ones is what a cadence needs.
        transitions = np.diff(loud.astype(int))
        self.assertGreaterEqual(
            int(np.sum(transitions == -1)), 2,
            "expected the ring to fall silent between repeats at least twice")


if __name__ == "__main__":
    unittest.main()
