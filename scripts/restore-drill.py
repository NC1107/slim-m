#!/usr/bin/env python3
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Restores a scripts/backup.py snapshot into a scratch location and checks
it, rather than trusting a backup nobody has ever restored.

The real logic and its full documentation live in
scripts/lib/restore_drill_lib.py, which scripts/lib/test_restore_drill_lib.py
exercises directly; this file is only the command-line entry point, kept
thin so the tests need no subprocess.

    python3 scripts/restore-drill.py --backup-root /path/to/backups
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))

from restore_drill_lib import parse_args, run  # noqa: E402

if __name__ == "__main__":
    sys.exit(run(parse_args(sys.argv[1:])))
