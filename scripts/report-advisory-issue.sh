#!/usr/bin/env bash
# Opens a GitHub issue when the scheduled advisory scan finds something, and
# closes it again once the tree comes back clean.
#
# The scan itself lives in advisory-watchdog.yml, because the pinned
# cargo-deny action is what runs it; this is only the reporting half, split
# out for the same reason check-e2e-red-streak.sh is - so the part with real
# branching can be driven against a fixture instead of only in production.
#
# Reporting by issue rather than by this job's own colour is deliberate, and
# is the whole point: docs/ci.md already records why advisories must not
# redden an unrelated pull request, and a scheduled workflow that only fails
# itself is a second red tab nobody opens - the exact failure the e2e red
# streak watchdog exists to correct. An issue is durable, deduplicated, and
# closes itself when the cause goes away.
#
# Reads ADVISORY_STATUS ("clean" or "found") and RUN_URL from the
# environment. GH_TOKEN and GITHUB_REPOSITORY come from the workflow.
set -euo pipefail

LABEL="${WATCHDOG_LABEL:-security-advisory}"
TITLE="${WATCHDOG_TITLE:-a dependency has an open security advisory}"
STATUS="${ADVISORY_STATUS:?ADVISORY_STATUS must be clean or found}"
RUN_URL="${RUN_URL:-}"

case "$STATUS" in
clean | found) ;;
*)
  echo "ADVISORY_STATUS must be clean or found, got: $STATUS" >&2
  exit 2
  ;;
esac

existing="$(gh issue list --repo "$GITHUB_REPOSITORY" --label "$LABEL" \
  --state open --limit 1 --json number --jq '.[0].number // empty')"

if [ "$STATUS" = "found" ]; then
  if [ -n "$existing" ]; then
    echo "advisory issue #$existing is already open; leaving it alone"
    exit 0
  fi
  gh label create "$LABEL" --repo "$GITHUB_REPOSITORY" --color B60205 \
    --description "an open advisory against a dependency" 2>/dev/null || true
  body="$(
    cat <<EOF
\`cargo deny check advisories\` reported at least one advisory against a
dependency in \`Cargo.lock\`.

The run log names each advisory, the crate it is against, and the version
range affected: $RUN_URL

To reproduce locally:

    cargo deny check advisories

This check runs on a schedule rather than on pull requests, so nothing is
blocked by it right now. It is reported as an issue so a real advisory cannot
sit unnoticed, which is what would happen if a scheduled job only failed
itself.

This issue closes itself on the next scheduled run that comes back clean.
EOF
  )"
  gh issue create --repo "$GITHUB_REPOSITORY" \
    --title "$TITLE" --label "$LABEL" --body "$body" >/dev/null
  echo "opened an advisory issue"
  exit 0
fi

if [ -n "$existing" ]; then
  gh issue close "$existing" --repo "$GITHUB_REPOSITORY" \
    --comment "No advisories reported on the latest scheduled scan; closing." >/dev/null
  echo "closed advisory issue #$existing"
else
  echo "no advisories, nothing open"
fi
