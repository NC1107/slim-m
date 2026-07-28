# SPDX-License-Identifier: Apache-2.0
"""Write the files the run uploads.

Generated rather than committed: they are two tiny PNGs, and a binary in the
tree is one more thing to keep and no easier to read than the code that makes
it. The bytes are a real PNG because the server sniffs the content type from
them and refuses anything it does not recognise.
"""
import struct
import sys
import zlib
from pathlib import Path


def png(path, width, height, rgb):
    """The smallest honest PNG: one solid colour, no filtering surprises."""
    raw = b"".join(
        b"\x00" + bytes(rgb) * width for _ in range(height))

    def chunk(kind, payload):
        body = kind + payload
        return (struct.pack(">I", len(payload)) + body
                + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    data = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw))
            + chunk(b"IEND", b""))
    Path(path).write_bytes(data)
    return len(data)


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    avatar = png(out / "avatar.png", 64, 64, (88, 180, 216))
    attachment = png(out / "attachment.png", 120, 80, (27, 111, 145))
    print(f"  fixtures: avatar.png {avatar}B, attachment.png {attachment}B")


if __name__ == "__main__":
    main()
