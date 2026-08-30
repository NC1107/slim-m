# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""The one implementation of partials, envelope and normalisation.

Every sound in the family imports this rather than carrying its own DSP, which
is what keeps them a family: one bell-like timbre, and the sounds differ only
by pitch contour, note count and duration.

The timbre is a fundamental plus two slightly inharmonic partials. Inharmonic
on purpose: exact 2x and 3x multiples read as an organ, and the small stretch
is what makes a struck-metal sound instead.

Determinism is a requirement here, not a nicety. The generated WAVs are
committed and CI regenerates and diffs them, so anything that varied by
machine, library version or clock would turn that gate into noise. Nothing
here is random, and the float-to-int16 rounding is fixed rather than left to
the platform.
"""
from __future__ import annotations

import wave
from dataclasses import dataclass
from pathlib import Path

import numpy as np

SAMPLE_RATE = 48_000

# Where the family sits. Notification audio is normalised relative to itself,
# not to any absolute room level: the point is that no sound in the set is
# startling next to another, which is a comparison between them and not a
# claim about how loud a given speaker will play them.
TARGET_LUFS = -20.0

# BS.1770 gates on 400ms blocks. Every sound here is between one and three
# blocks long, which is where a gated measurement stops being steady: it is
# defined for broadcast programme material, not for a 300ms chime.
MIN_GATED_SECONDS = 0.4

# The two inharmonic partials, as multiples of the fundamental, with the
# amplitude each contributes. Kept low relative to the fundamental (backlog
# #134: the original 0.42/0.17 pair read as a bright, jarring clang) so the
# family stays a soft, simple chime rather than a struck-metal blast.
_PARTIALS = ((1.0, 1.00), (2.02, 0.24), (3.05, 0.08))


@dataclass(frozen=True)
class Note:
    """One struck note: when it starts, how high, and how long it rings."""

    start: float
    frequency: float
    seconds: float
    gain: float = 1.0


def _envelope(samples: int, seconds: float) -> np.ndarray:
    """A soft-struck envelope: gentle attack, exponential decay.

    Backlog #134 asked for something closer to an OS boot chime than the
    click the previous 4ms attack produced. 12ms is inside this family's own
    original 10-15ms target (docs/research/audio.md) and is still short
    enough to read as a strike rather than a swell; the exponential tail is
    what a real bell does. A linear fade sounds like someone turning a knob.
    """
    t = np.linspace(0.0, seconds, samples, endpoint=False)
    attack = np.clip(t / 0.012, 0.0, 1.0)
    decay = np.exp(-t * (4.6 / seconds))
    return attack * decay


def bell(note: Note) -> np.ndarray:
    """One note of the family's timbre."""
    samples = int(round(note.seconds * SAMPLE_RATE))
    t = np.linspace(0.0, note.seconds, samples, endpoint=False)
    voice = np.zeros(samples, dtype=np.float64)
    for multiple, amplitude in _PARTIALS:
        voice += amplitude * np.sin(2.0 * np.pi * note.frequency * multiple * t)
    return voice * _envelope(samples, note.seconds) * note.gain


def render(notes: list[Note], tail: float = 0.05) -> np.ndarray:
    """Lay the notes onto one timeline, overlapping where they overlap."""
    end = max(n.start + n.seconds for n in notes) + tail
    out = np.zeros(int(round(end * SAMPLE_RATE)), dtype=np.float64)
    for note in notes:
        rendered = bell(note)
        at = int(round(note.start * SAMPLE_RATE))
        out[at:at + rendered.size] += rendered
    return out


def _k_weighted(signal: np.ndarray) -> np.ndarray:
    """BS.1770 K-weighting: a head-shelf then a high-pass, at 48 kHz.

    Written out rather than taken from a library because the fallback below
    has to agree in character with the gated path, and because these
    coefficients are part of the reproducibility contract the diff gate rests
    on.
    """
    stages = (
        ((1.53512485958697, -2.69169618940638, 1.19839281085285),
         (1.0, -1.69065929318241, 0.73248077421585)),
        ((1.0, -2.0, 1.0),
         (1.0, -1.99004745483398, 0.99007225036621)),
    )
    out = signal.astype(np.float64)
    for b, a in stages:
        filtered = np.zeros_like(out)
        x1 = x2 = y1 = y2 = 0.0
        for i, x0 in enumerate(out):
            y0 = (b[0] * x0 + b[1] * x1 + b[2] * x2
                  - a[1] * y1 - a[2] * y2) / a[0]
            filtered[i] = y0
            x2, x1 = x1, x0
            y2, y1 = y1, y0
        out = filtered
    return out


# The window a brief sound is judged over. Long enough to be a loudness and
# not a peak, short enough that a 300ms chime and a 1.3s ring are compared on
# the same thing: the loudest moment each has.
SHORT_TERM_SECONDS = 0.2


def loudness(signal: np.ndarray) -> float:
    """The loudest short-term K-weighted moment in the clip, in LUFS.

    Not the whole-clip average and not BS.1770 integrated, and both of those
    were tried first. The strategy called for pyloudnorm with a whole-clip
    fallback under 400ms; built that way the family spanned 3.4 dB on any one
    consistent scale, because the two meters disagree and nothing compared
    them. Whole-clip averaging then still spanned 3.2 dB, for a different
    reason: it judges a 0.29s chime and a 1.29s ring by how much of each is
    decay tail, which is a fact about their lengths rather than about how loud
    they sound.

    A brief sound is heard as its loudest moment, so that is what is measured
    and matched. It is defined identically at every length, needs no gating
    floor, and depends on no third-party version inside the reproducibility
    gate.
    """
    weighted = _k_weighted(signal)
    window = int(SHORT_TERM_SECONDS * SAMPLE_RATE)
    squared = weighted ** 2
    if squared.size <= window:
        mean_square = float(np.mean(squared))
    else:
        # Sliding mean square, by prefix sums: one pass, exact, no scipy.
        cumulative = np.concatenate([[0.0], np.cumsum(squared)])
        sums = cumulative[window:] - cumulative[:-window]
        mean_square = float(np.max(sums) / window)
    if mean_square <= 0.0:
        return float("-inf")
    return -0.691 + 10.0 * np.log10(mean_square)


def gated_loudness(signal: np.ndarray) -> float:
    """BS.1770 integrated loudness, for checking rather than for setting.

    Kept apart from [loudness] so nothing normalises with it by accident.
    """
    import pyloudnorm

    meter = pyloudnorm.Meter(SAMPLE_RATE)
    return float(meter.integrated_loudness(signal))


def normalise(signal: np.ndarray, target: float = TARGET_LUFS) -> np.ndarray:
    """Bring the clip to [target], then keep it inside full scale.

    The ceiling is applied after the gain, not instead of it: a clip that
    would clip is turned down as a whole rather than having its peaks
    flattened, since flattening is audible and a couple of dB is not.
    """
    measured = loudness(signal)
    if measured == float("-inf"):
        return signal
    out = signal * (10.0 ** ((target - measured) / 20.0))
    peak = float(np.max(np.abs(out)))
    ceiling = 10.0 ** (-1.0 / 20.0)
    if peak > ceiling:
        out = out * (ceiling / peak)
    return out


def write_wav(path: Path, signal: np.ndarray) -> int:
    """Write 16-bit mono, rounding the same way on every machine."""
    clipped = np.clip(signal, -1.0, 1.0)
    ints = np.round(clipped * 32767.0).astype("<i2")
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(SAMPLE_RATE)
        out.writeframes(ints.tobytes())
    return path.stat().st_size
