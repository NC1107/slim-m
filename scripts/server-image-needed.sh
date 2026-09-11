#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# Says whether main-builds needs to publish a server image, by asking what is
# actually deployed rather than what this push happened to touch.
#
# The push's own diff is the wrong question. `main-builds.yml` sets
# `cancel-in-progress: true`, so a server build can be cancelled by a later
# client-only push whose own filter then reports `server: false`, and no push
# afterwards ever picks it up. On 2026-09-10 that left two merged server fixes
# unpublished while every run reported success, because a skipped job is a
# successful run. See docs/ci.md's concurrency section.
#
# So: find the newest run whose `server-image` job really succeeded, and treat
# anything under `crates/**` that moved since then as needing an image. When no
# such run can be found - a short history, a GitHub hiccup, an unreachable
# commit - this prints nothing and says nothing, leaving the paths filter as
# the only voice. That is the old behaviour, which is the safe direction to
# fail in: an extra build costs minutes, a missed one costs a deploy.
#
# Writes `server=true` to $GITHUB_OUTPUT only when it is sure. Never false:
# the filter beside it owns that answer.
set -euo pipefail

current_sha="${1:?usage: server-image-needed.sh <current-sha>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

runs=$(gh run list --workflow main-builds.yml --branch main \
  --limit 25 --json databaseId 2>/dev/null || echo '[]')

detailed='[]'
for id in $(jq -r '.[].databaseId' <<<"$runs"); do
  one=$(gh run view "$id" --json headSha,jobs 2>/dev/null || echo 'null')
  detailed=$(jq -c --argjson r "$one" '. + [$r]' <<<"$detailed")
done

base=$(jq -c 'map(select(. != null))' <<<"$detailed" \
  | python3 "$here/lib/server_image_base.py" "$current_sha")

if [ -z "$base" ]; then
  echo "no published server image in recent history; the push diff decides alone"
  exit 0
fi

git fetch --quiet origin "$base" 2>/dev/null || true
if ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
  echo "last published commit $base is unreachable; the push diff decides alone"
  exit 0
fi

if git diff --name-only "$base"..HEAD -- crates/ | grep -q .; then
  echo "crates/ moved since $base, which is the commit latest holds"
  echo "server=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"
else
  echo "crates/ unchanged since $base"
fi
