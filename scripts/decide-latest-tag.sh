#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Prints "true" on stdout if VERSION is at least as new, by `sort -V`, as
# every semver-shaped tag GHCR already has published for IMAGE, else "false"
# with a reason on stderr. A deployment auto-updates against :latest, so
# server-image-merge uses this to refuse to move it backwards when an old
# server-v* tag is re-pushed. See docs/ci.md's server-image-merge section.

set -euo pipefail

image="$1"
version="$2"
package="${image#ghcr.io/nc1107/}"

published="$(gh api --paginate \
  "users/nc1107/packages/container/${package}/versions" \
  --jq '.[].metadata.container.tags[]' 2>/dev/null \
  | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)"
newest="$(printf '%s\n%s\n' "$version" "$published" | sort -V | tail -n1)"

if [ "$newest" = "$version" ]; then
  echo true
else
  echo "${version} is older than the newest published tag (${newest}); :latest is left where it is." >&2
  echo false
fi
