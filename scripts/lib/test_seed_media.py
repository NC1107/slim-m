# SPDX-License-Identifier: Apache-2.0
"""Unit coverage for the generated attachment fixtures.

Checks structure the server's own sniffer cares about (real magic bytes,
declared dimensions matching what was asked for) and a couple of visual
properties (a gradient's two ends differ, a checkerboard is two colours,
noise is not a solid fill) - not exact bytes, since none of that is a
contract worth pinning.
"""
import random
import struct
import sys
import tempfile
import unittest
import wave
import zipfile
import zlib
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))

import seed_media  # noqa: E402


def _tmp_path(case, suffix):
    """A path the file at it is removed when `case` tears down, whether or
    not the test that asked for it wrote anything there."""
    handle = tempfile.NamedTemporaryFile(suffix=suffix, delete=False)
    handle.close()
    case.addCleanup(lambda: Path(handle.name).unlink(missing_ok=True))
    return Path(handle.name)


def _dimensions(png_bytes):
    return struct.unpack(">II", png_bytes[16:24])


def _decode_rows(png_bytes):
    """The raw scanlines (leading filter byte stripped), for a filter-0,
    non-interlaced RGB8 image only - all this module ever emits."""
    width, _height = _dimensions(png_bytes)
    idat = b""
    offset = 8
    while offset < len(png_bytes):
        length = struct.unpack(">I", png_bytes[offset:offset + 4])[0]
        kind = png_bytes[offset + 4:offset + 8]
        payload = png_bytes[offset + 8:offset + 8 + length]
        if kind == b"IDAT":
            idat += payload
        offset += 8 + length + 4
    raw = zlib.decompress(idat)
    stride = 1 + width * 3
    return [raw[i + 1:i + stride] for i in range(0, len(raw), stride)]


class PngStructureTest(unittest.TestCase):
    def test_every_generator_produces_real_png_magic_bytes(self):
        cases = [
            lambda p: seed_media.gradient_png(p, 10, 10, (0, 0, 0), (255, 255, 255)),
            lambda p: seed_media.checkerboard_png(p, 10, 10, (0, 0, 0), (255, 255, 255)),
            lambda p: seed_media.rings_png(p, 10, 10, (0, 0, 0), (255, 255, 255)),
            lambda p: seed_media.noise_png(p, 10, 10, random.Random(1)),
        ]
        for build in cases:
            path = _tmp_path(self, ".png")
            build(path)
            self.assertEqual(path.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")

    def test_declared_dimensions_match_what_was_asked_for(self):
        path = _tmp_path(self, ".png")
        seed_media.gradient_png(path, 37, 21, (0, 0, 0), (255, 255, 255))
        self.assertEqual(_dimensions(path.read_bytes()), (37, 21))

    def test_reported_length_matches_the_written_file(self):
        path = _tmp_path(self, ".png")
        reported = seed_media.gradient_png(path, 12, 12, (0, 0, 0), (1, 1, 1))
        self.assertEqual(reported, len(path.read_bytes()))


class GradientTest(unittest.TestCase):
    def test_x_axis_gradient_differs_from_left_to_right(self):
        path = _tmp_path(self, ".png")
        seed_media.gradient_png(path, 100, 4, (0, 0, 0), (255, 255, 255), axis="x")
        first_row = _decode_rows(path.read_bytes())[0]
        self.assertNotEqual(first_row[0:3], first_row[-3:])

    def test_y_axis_gradient_differs_from_top_to_bottom(self):
        path = _tmp_path(self, ".png")
        seed_media.gradient_png(path, 4, 100, (0, 0, 0), (255, 255, 255), axis="y")
        rows = _decode_rows(path.read_bytes())
        self.assertNotEqual(rows[0][0:3], rows[-1][0:3])


class CheckerboardTest(unittest.TestCase):
    def test_uses_exactly_the_two_given_colours(self):
        path = _tmp_path(self, ".png")
        seed_media.checkerboard_png(path, 16, 16, (10, 20, 30), (200, 210, 220), cell=4)
        seen = set()
        for row in _decode_rows(path.read_bytes()):
            for i in range(0, len(row), 3):
                seen.add(row[i:i + 3])
        self.assertEqual(seen, {bytes((10, 20, 30)), bytes((200, 210, 220))})


class RingsTest(unittest.TestCase):
    def test_alternates_between_both_given_colours(self):
        path = _tmp_path(self, ".png")
        seed_media.rings_png(path, 41, 41, (0, 0, 0), (255, 255, 255), ring_width=6)
        seen = {row[i:i + 3] for row in _decode_rows(path.read_bytes())
                 for i in range(0, len(row), 3)}
        self.assertEqual(seen, {bytes((0, 0, 0)), bytes((255, 255, 255))})


class NoiseTest(unittest.TestCase):
    def test_is_reproducible_under_the_same_rng_seed(self):
        path_a, path_b = _tmp_path(self, ".png"), _tmp_path(self, ".png")
        seed_media.noise_png(path_a, 20, 20, random.Random(42))
        seed_media.noise_png(path_b, 20, 20, random.Random(42))
        self.assertEqual(path_a.read_bytes(), path_b.read_bytes())

    def test_is_not_a_solid_fill(self):
        path = _tmp_path(self, ".png")
        seed_media.noise_png(path, 20, 20, random.Random(1))
        self.assertGreater(len({row[0:3] for row in _decode_rows(path.read_bytes())}), 1)

    def test_stored_level_size_is_close_to_the_raw_pixel_count(self):
        path = _tmp_path(self, ".png")
        width, height = 200, 100
        seed_media.noise_png(path, width, height, random.Random(1), level=0)
        raw_size = height * (1 + width * 3)
        self.assertLess(abs(len(path.read_bytes()) - raw_size), raw_size * 0.05)


class PdfTest(unittest.TestCase):
    def test_starts_with_the_real_pdf_magic_bytes(self):
        path = _tmp_path(self, ".pdf")
        seed_media.pdf(path, "Title", ["one", "two"])
        self.assertTrue(path.read_bytes().startswith(b"%PDF-"))

    def test_has_a_well_formed_xref_and_trailer(self):
        path = _tmp_path(self, ".pdf")
        seed_media.pdf(path, "Title", ["one"])
        data = path.read_bytes()
        self.assertIn(b"\nxref\n", data)
        self.assertIn(b"\ntrailer\n", data)
        self.assertTrue(data.rstrip().endswith(b"%%EOF"))

    def test_xref_offsets_point_at_their_own_object(self):
        path = _tmp_path(self, ".pdf")
        seed_media.pdf(path, "Title", ["one", "two", "three"])
        data = path.read_bytes()
        xref_start = data.index(b"\nxref\n") + 1
        trailer_start = data.index(b"trailer")
        entries = data[xref_start:trailer_start].splitlines()[3:]
        for index, entry in enumerate(entries, start=1):
            offset = int(entry.split()[0])
            self.assertTrue(data[offset:].startswith(f"{index} 0 obj".encode()))

    def test_escapes_parentheses_in_body_text(self):
        path = _tmp_path(self, ".pdf")
        seed_media.pdf(path, "Title", ["a (note) here"])
        self.assertIn(b"a \\(note\\) here", path.read_bytes())

    def test_reported_length_matches_the_written_file(self):
        path = _tmp_path(self, ".pdf")
        reported = seed_media.pdf(path, "Title", ["one"])
        self.assertEqual(reported, len(path.read_bytes()))


class PlainTextTest(unittest.TestCase):
    def test_writes_real_utf8_text_joined_by_newlines(self):
        path = _tmp_path(self, ".log")
        seed_media.plain_text(path, ["first line", "second line"])
        self.assertEqual(path.read_text("utf-8"), "first line\nsecond line")

    def test_reported_length_matches_the_written_file(self):
        path = _tmp_path(self, ".log")
        reported = seed_media.plain_text(path, ["one", "two"])
        self.assertEqual(reported, len(path.read_bytes()))


class ZipArchiveTest(unittest.TestCase):
    def test_writes_a_real_zip_with_every_entry_readable(self):
        path = _tmp_path(self, ".zip")
        seed_media.zip_archive(
            path, [("a.txt", b"hello"), ("b.json", b'{"x": 1}')])
        with zipfile.ZipFile(path) as archive:
            self.assertEqual(archive.read("a.txt"), b"hello")
            self.assertEqual(archive.read("b.json"), b'{"x": 1}')

    def test_reported_length_matches_the_written_file(self):
        path = _tmp_path(self, ".zip")
        reported = seed_media.zip_archive(path, [("a.txt", b"hello")])
        self.assertEqual(reported, len(path.read_bytes()))


class WavToneTest(unittest.TestCase):
    def test_writes_a_real_mono_16_bit_pcm_wav(self):
        path = _tmp_path(self, ".wav")
        seed_media.wav_tone(path, random.Random(1), seconds=0.1, sample_rate=8000)
        with wave.open(str(path), "rb") as wav_file:
            self.assertEqual(wav_file.getnchannels(), 1)
            self.assertEqual(wav_file.getsampwidth(), 2)
            self.assertEqual(wav_file.getframerate(), 8000)
            self.assertGreater(wav_file.getnframes(), 0)

    def test_is_reproducible_under_the_same_rng_seed(self):
        path_a, path_b = _tmp_path(self, ".wav"), _tmp_path(self, ".wav")
        seed_media.wav_tone(path_a, random.Random(7), seconds=0.05)
        seed_media.wav_tone(path_b, random.Random(7), seconds=0.05)
        self.assertEqual(path_a.read_bytes(), path_b.read_bytes())

    def test_reported_length_matches_the_written_file(self):
        path = _tmp_path(self, ".wav")
        reported = seed_media.wav_tone(path, random.Random(1), seconds=0.05)
        self.assertEqual(reported, len(path.read_bytes()))


class Mp4ClipTest(unittest.TestCase):
    """No real ffmpeg here: a CI runner or a contributor's machine may not
    have it, and `ffmpeg_available()` exists exactly so callers can skip
    cleanly rather than this module assuming it is always present."""

    def test_available_reflects_whether_ffmpeg_is_on_path(self):
        with patch("shutil.which", return_value="/usr/bin/ffmpeg"):
            self.assertTrue(seed_media.ffmpeg_available())
        with patch("shutil.which", return_value=None):
            self.assertFalse(seed_media.ffmpeg_available())

    def test_invokes_ffmpeg_with_a_synthetic_source_and_no_prompt(self):
        path = _tmp_path(self, ".mp4")
        with patch("seed_media.subprocess.run") as run:
            run.return_value.returncode = 0
            path.write_bytes(b"stand-in bytes")
            seed_media.mp4_clip(path, seconds=1, width=64, height=48)
        args = run.call_args[0][0]
        self.assertIn("-f", args)
        self.assertIn("lavfi", args)
        self.assertIn("testsrc=duration=1:size=64x48:rate=15", args)
        self.assertTrue(run.call_args.kwargs.get("check"))


if __name__ == "__main__":
    unittest.main()
