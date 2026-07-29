# SPDX-License-Identifier: Apache-2.0
"""The seven sounds, as contours over the shared timbre.

Each is a list of notes and nothing else: the timbre, envelope and loudness
all come from synth.py, so the only thing that distinguishes one sound from
another is its pitch contour, its note count and how long it rings. That is
the whole point of the family, and it is why these live as data here rather
than as seven scripts that each grew their own DSP.

The pitches are a pentatonic set, so any two sounds landing at once still
agree with each other. Join and leave are the same three notes in opposite
order, which is what makes them read as a pair rather than as two unrelated
events.
"""
from __future__ import annotations

from synth import Note

# A pentatonic ladder in Hz, roughly A4 up. Named so a contour reads as a
# shape rather than as a list of numbers.
A4, C5, D5, E5, G5, A5, C6, D6 = (
    440.0, 523.25, 587.33, 659.25, 783.99, 880.0, 1046.50, 1174.66,
)

# name -> (notes, what it is for). The description rides along because a
# sound file's name is the only documentation most people ever see.
SOUNDS: dict[str, tuple[list[Note], str]] = {
    "direct_message": (
        [Note(0.00, A5, 0.30)],
        "One note. A direct message is the single most personal event, so it "
        "gets the simplest sound in the set.",
    ),
    "mention": (
        [Note(0.00, A5, 0.26), Note(0.11, D6, 0.34)],
        "Two rising notes. A mention is a direct message with an edge, so it "
        "is the direct-message note plus a lift.",
    ),
    "group_message": (
        [Note(0.00, E5, 0.24)],
        "One note, lower and shorter than a direct message. The most frequent "
        "event in the set, so it is the least insistent thing that still "
        "registers.",
    ),
    "call_ring": (
        [
            Note(0.00, C5, 0.34), Note(0.16, G5, 0.40),
            Note(0.62, C5, 0.34), Note(0.78, G5, 0.46),
        ],
        "A repeating two-note figure. The only sound meant to be heard from "
        "another room, so it is the longest and the only one that repeats.",
    ),
    "member_join": (
        [Note(0.00, C5, 0.20), Note(0.09, E5, 0.20), Note(0.18, G5, 0.30)],
        "Three notes ascending. Someone arrived.",
    ),
    "member_leave": (
        [Note(0.00, G5, 0.20), Note(0.09, E5, 0.20), Note(0.18, C5, 0.30)],
        "The same three notes descending. Someone left. Mirrored on purpose "
        "so the pair is learnable without being told.",
    ),
    "error": (
        [Note(0.00, D5, 0.22), Note(0.10, A4, 0.34)],
        "Two notes falling a fourth. The only interval in the set that is not "
        "from the pentatonic ladder, so it is the only one that sounds wrong "
        "on purpose.",
    ),
}
