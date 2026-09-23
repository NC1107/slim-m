#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Detects a merged release PR that release-please never finished processing:
# still carrying `autorelease: pending` long after it merged.
#
# That label is release-please's own record of "this PR is still owed a
# GitHub release". While it is set, every subsequent release-please run
# re-attempts that release first, fails, and never reaches the part where it
# would propose the next one. Nothing else notices: the merge looks normal,
# main keeps moving, and the only trace is a red release run that reads like
# a transient token error.
#
# It is not hypothetical. On 2026-09-23 client-v0.81.0's tag and release
# were recovered by hand after its own run failed, which left the label
# behind; the next three release runs on main failed against an already
# finished release, and no release PR was proposed for sixteen merged
# commits until somebody went looking.
#
# The sibling of scripts/check-release-tag-lag.sh, which asks the git
# history whether a manifest bump grew a tag. This one asks the API a
# question git cannot answer, so it needs a token; see the watchdog.
#
# A freshly merged release PR is normally relabelled within the same run, so
# GRACE_SECONDS is how long that is allowed to take before a still-pending
# label is reported as stuck rather than in flight. NOW_EPOCH and
# PENDING_JSON are both overridable so a test can run this against fixed
# input instead of the real clock and the real API.

set -euo pipefail

GRACE_SECONDS="${GRACE_SECONDS:-1800}"
NOW_EPOCH="${NOW_EPOCH:-$(date +%s)}"

if [[ -n "${PENDING_JSON:-}" ]]; then
  pending="$(cat "$PENDING_JSON")"
else
  pending="$(gh pr list --state merged --label 'autorelease: pending' \
    --limit 20 --json number,title,mergedAt)"
fi

stuck=0

while IFS=$'\t' read -r number title merged_at; do
  [[ -n "$number" ]] || continue
  merged_epoch="$(date -u -d "$merged_at" +%s)"
  age=$((NOW_EPOCH - merged_epoch))
  if ((age < GRACE_SECONDS)); then
    echo "ok: #${number} merged ${age}s ago, still inside the grace window"
    continue
  fi
  stuck=1
  echo "::error::#${number} (${title}) merged ${age}s ago and is still labelled" \
    "'autorelease: pending'. release-please will retry its release on every" \
    "push to main and fail, proposing nothing new. If that release really did" \
    "happen, relabel it: gh pr edit ${number} --remove-label 'autorelease:" \
    "pending' --add-label 'autorelease: tagged'"
done < <(echo "$pending" | jq -r '.[] | [.number, .title, .mergedAt] | @tsv')

if ((stuck == 0)); then
  echo "release labels: no merged release PR is stuck pending"
fi

exit "$stuck"
