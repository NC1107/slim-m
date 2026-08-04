# SPDX-License-Identifier: Apache-2.0
"""Guards e2e_labels.py against drifting out from under the client.

Each constant here is a string this harness clicks or waits for by exact
substring match against the client's accessible names. `L.JOIN_CALL` sat
here for a full release cycle after PR #354 removed the join lobby it named,
and the only symptom was a run failing at "never saw 'Join call'" - a name
that reads as plausible right up until something actually runs it. This test
catches that class of drift in seconds, at unit-test speed, rather than
after the 60-minute stack in scripts/e2e.sh boots.
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import e2e_labels as L  # noqa: E402

CLIENT_LIB = Path(__file__).resolve().parents[2] / "client" / "packages" / "app" / "lib"

# Fixture content the seed script writes (a channel name, a message body), never a widget's own label.
NOT_A_LABEL = {"TEXT_CHANNEL", "VOICE_CHANNEL", "FIRST_MESSAGE", "REPLY_MESSAGE"}


def label_constants():
    for name, value in vars(L).items():
        if name.startswith("_") or name in NOT_A_LABEL:
            continue
        if name.isupper() and isinstance(value, str):
            yield name, value


class LabelsStillExistTest(unittest.TestCase):
    """Every accessible-name constant must appear somewhere in the client."""

    def test_every_label_appears_in_client_source(self):
        sources = list(CLIENT_LIB.rglob("*.dart"))
        self.assertTrue(sources, f"no .dart files found under {CLIENT_LIB}")
        contents = [p.read_text(encoding="utf-8", errors="ignore") for p in sources]
        stale = [name for name, value in label_constants()
                 if not any(value in text for text in contents)]
        self.assertEqual(
            stale, [],
            f"e2e_labels.py still names {stale}, but no .dart file under "
            f"{CLIENT_LIB} carries that string any more - the widget was "
            "renamed or removed and the harness needs updating to match")


if __name__ == "__main__":
    unittest.main()
