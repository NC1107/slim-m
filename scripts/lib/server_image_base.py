# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
"""Which commit the last published server image was built from.

`main-builds.yml` decides whether to build a server image from the push's own
diff. That is the wrong question, and on 2026-09-10 it cost a day of undeployed
server fixes: `cancel-in-progress: true` cancelled the run that had server
changes, the client-only push that cancelled it reported `server: false`, and
`server-image` was skipped by every run afterwards. Both runs ended green,
because a skipped job is a successful run.

The right question is "has the server changed since the image that is actually
out there", and this answers the half of it a workflow expression cannot: the
commit of the most recent `main-builds` run whose `server-image` job really
succeeded. The caller diffs `crates/**` between that commit and HEAD.

Reads a run list on stdin rather than calling the API itself, so the network
belongs to the workflow step and the decision is unit-testable here.
"""
import json
import sys


def base_sha(runs, skip_sha=None):
    """The head SHA of the newest run in `runs` that published a server image.

    `runs` is newest-first, each entry `{"headSha": ..., "conclusion": ...,
    "jobs": [{"name": ..., "conclusion": ...}]}`. Returns None when no such run
    exists, which the caller must read as "cannot tell" and fall back to the
    push's own diff - never as "nothing to build", since that is the failure
    this whole thing exists to stop.

    `skip_sha` drops the run for the commit being built right now. A rerun of
    the current commit would otherwise report itself as already published.
    """
    for run in runs:
        head = run.get("headSha")
        if not head or head == skip_sha:
            continue
        for job in run.get("jobs") or []:
            if job.get("name") == "server-image" and job.get("conclusion") == "success":
                return head
    return None


def main(argv):
    skip = argv[1] if len(argv) > 1 else None
    try:
        runs = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        # An unreadable answer is "cannot tell", and the caller falls back.
        print("")
        return 0
    if not isinstance(runs, list):
        print("")
        return 0
    print(base_sha(runs, skip) or "")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
