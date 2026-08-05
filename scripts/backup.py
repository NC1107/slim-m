#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Takes a consistent backup of the database and the attachment/avatar bytes
Litestream does not cover (see deploy/README.md's "Backups" section).

The real logic and its full documentation live in scripts/lib/backup_lib.py,
which scripts/lib/test_backup_lib.py exercises directly; this file is only
the command-line entry point, kept thin so the tests need no subprocess.

    python3 scripts/backup.py --backup-root /path/to/backups \\
        --database-path /data/slimm.db --media-dir /data/media

Run this against the running server's volume from a throwaway container
that has Python (the shipped server image is distroless and has none):

    docker run --rm -v slimm_data:/data:ro -v "$(pwd)/scripts":/scripts:ro \\
        -v /path/on/host/backups:/backup python:3-slim \\
        python3 /scripts/backup.py --backup-root /backup \\
        --database-path /data/slimm.db --media-dir /data/media
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))

from backup_lib import parse_args, run  # noqa: E402

if __name__ == "__main__":
    sys.exit(run(parse_args(sys.argv[1:])))
