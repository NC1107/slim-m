# SPDX-License-Identifier: Apache-2.0
"""Generates the varied attachment fixtures a seeding run uploads.

Everything here is a real, structurally valid file, generated in-process
rather than committed as a binary: the server sniffs content type from bytes
(`crates/slimm-server/src/media.rs`), never from a filename or a declared
Content-Type, so anything not a genuine PNG or PDF is simply refused.

Every PNG below is a real RGB8, non-interlaced image with actual pixel
variation - a gradient, a checkerboard, concentric rings, or noise - never a
single flat fill, so a transcript of several reads as visibly different
attachments rather than four identical swatches. The PDF is a minimal but
real one: a Catalog, a Pages tree, one Page, a Type1 font, a content stream,
and a byte-accurate xref table, not just a `%PDF-` prefix glued onto other
bytes.
"""
import struct
import zlib
from pathlib import Path


def _png(width, height, rows, level=6):
    """Assembles PNG bytes from `rows`: `height` byte strings, each a
    leading filter-type-0 byte followed by `width` RGB8 pixels."""
    raw = b"".join(rows)

    def chunk(kind, payload):
        body = kind + payload
        return (struct.pack(">I", len(payload)) + body
                + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw, level))
            + chunk(b"IEND", b""))


def _solid_row(width, rgb):
    return b"\x00" + bytes(rgb) * width


def gradient_png(path, width, height, start, end, axis="x"):
    """A linear gradient between two RGB tuples along one axis.

    Cheap by construction: an `axis="x"` gradient is the same row repeated
    `height` times (computed once), and an `axis="y"` gradient is one solid
    colour per row (computed `height` times, never `width * height`).
    """
    if axis == "x":
        row = bytearray(b"\x00")
        for x in range(width):
            t = x / max(width - 1, 1)
            row += bytes(int(a + (b - a) * t) for a, b in zip(start, end))
        rows = [bytes(row)] * height
    else:
        rows = []
        for y in range(height):
            t = y / max(height - 1, 1)
            rgb = tuple(int(a + (b - a) * t) for a, b in zip(start, end))
            rows.append(_solid_row(width, rgb))
    data = _png(width, height, rows)
    Path(path).write_bytes(data)
    return len(data)


def checkerboard_png(path, width, height, rgb_a, rgb_b, cell=8):
    """A two-colour checkerboard, built one row of each parity, not one
    pixel at a time."""
    row_a = bytearray(b"\x00")
    row_b = bytearray(b"\x00")
    for x in range(width):
        first = (x // cell) % 2 == 0
        row_a += bytes(rgb_a if first else rgb_b)
        row_b += bytes(rgb_b if first else rgb_a)
    rows = [bytes(row_a) if (y // cell) % 2 == 0 else bytes(row_b)
            for y in range(height)]
    data = _png(width, height, rows)
    Path(path).write_bytes(data)
    return len(data)


def rings_png(path, width, height, rgb_a, rgb_b, ring_width=16):
    """Concentric rings around the image centre; genuinely per-pixel, so
    reserved for icon- or thumbnail-sized images."""
    cx, cy = (width - 1) / 2, (height - 1) / 2
    rows = []
    for y in range(height):
        row = bytearray(b"\x00")
        for x in range(width):
            dist = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            band = int(dist // ring_width) % 2 == 0
            row += bytes(rgb_a if band else rgb_b)
        rows.append(bytes(row))
    data = _png(width, height, rows)
    Path(path).write_bytes(data)
    return len(data)


def noise_png(path, width, height, rng, level=0):
    """Per-pixel random colour, sized by `width` and `height` alone.

    `level=0` (store, not deflate) makes the output size predictable: random
    bytes barely compress anyway, so this is the fixture meant to land near
    an upload ceiling on purpose, via its dimensions rather than a guess at
    a compression ratio. `rng` is the caller's own `random.Random`, so a
    `--seed` run reproduces this fixture's bytes exactly like every other.
    """
    rows = [b"\x00" + rng.randbytes(width * 3) for _ in range(height)]
    data = _png(width, height, rows, level=level)
    Path(path).write_bytes(data)
    return len(data)


def _escape_pdf(text):
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def pdf(path, title, lines):
    """A minimal, syntactically real one-page PDF: `title` as a heading and
    `lines` underneath, in Helvetica, on a Letter-sized page.

    Hand-built rather than templated from a library, because the point is a
    file the server's `%PDF-` sniff and a real reader both accept: a proper
    object table and a byte-accurate xref, not merely the right magic bytes.
    """
    ops = ["BT", "/F1 18 Tf", "72 740 Td", f"({_escape_pdf(title)}) Tj",
           "0 -28 Td", "/F1 11 Tf"]
    for line in lines:
        ops.append(f"({_escape_pdf(line)}) Tj")
        ops.append("0 -16 Td")
    ops.append("ET")
    content = "\n".join(ops).encode("latin-1")

    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 4 0 R >> >> "
        b"/MediaBox [0 0 612 792] /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        (f"<< /Length {len(content)} >>\nstream\n".encode("latin-1")
         + content + b"\nendstream"),
    ]

    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for index, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{index} 0 obj\n".encode("latin-1") + body + b"\nendobj\n"

    xref_offset = len(out)
    out += f"xref\n0 {len(objects) + 1}\n".encode("latin-1")
    out += b"0000000000 65535 f \n"
    for offset in offsets:
        out += f"{offset:010d} 00000 n \n".encode("latin-1")
    out += (f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\n"
            f"startxref\n{xref_offset}\n%%EOF").encode("latin-1")

    Path(path).write_bytes(bytes(out))
    return len(out)
