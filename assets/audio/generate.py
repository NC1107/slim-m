#!/usr/bin/env python3
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Regenerate every notification WAV from source.

The WAVs are committed and CI runs this and diffs, so a sound that drifts from
the code that claims to make it fails the build. Run it after touching either
synth.py or sounds.py:

    python3 assets/audio/generate.py

Prints what each sound measured, because the numbers are the reason to trust
that the family is level with itself.
"""
from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "notifications"))

import synth  # noqa: E402
from sounds import CALLKIT_RINGTONE, SOUNDS  # noqa: E402

OUT = HERE / "notifications"


def _render_one(name: str, notes: list[synth.Note]) -> None:
    rendered = synth.render(notes)
    levelled = synth.normalise(rendered)
    size = synth.write_wav(OUT / f"{name}.wav", levelled)

    seconds = levelled.size / synth.SAMPLE_RATE
    measured = synth.loudness(levelled)
    peak = float(abs(levelled).max())
    peak_db = 20.0 * (peak and __import__("math").log10(peak) or -99)
    print(f"{name:16} {seconds:8.3f} {measured:8.2f} {peak_db:10.2f} "
          f"{size:8d}")


def main() -> int:
    print(f"{'sound':16} {'seconds':>8} {'LUFS':>8} {'peak dBFS':>10} {'bytes':>8}")
    for name, (notes, _) in sorted(SOUNDS.items()):
        _render_one(name, notes)
    # Same renderer and diff gate, but not one of the seven; see sounds.py.
    _render_one("callkit_ringtone", CALLKIT_RINGTONE[0])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
