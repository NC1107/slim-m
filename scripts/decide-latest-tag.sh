#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Prints "true" on stdout if VERSION is at least as new, by `sort -V`, as
# every semver-shaped tag GHCR already has published for IMAGE, else "false"
# with a reason on stderr and a `::warning::` annotation. A deployment
# auto-updates against :latest, so server-image-merge uses this to refuse to
# move it backwards when an old server-v* tag is re-pushed. See docs/ci.md's
# server-image-merge section.
#
# A listing that cannot be read fails closed, the same as an old version:
# it answers "false" rather than treating "gh could not tell me" the same
# as "GHCR has nothing published yet".

set -euo pipefail

image="$1"
version="$2"
package="${image#ghcr.io/nc1107/}"

if ! raw="$(gh api --paginate \
  "users/nc1107/packages/container/${package}/versions" \
  --jq '.[].metadata.container.tags[]' 2>&1)"; then
  reason="$(printf '%s' "$raw" | tr '\n' ' ')"
  echo "::warning::could not list published tags for ${package} (${reason}); leaving :latest where it is" >&2
  echo false
  exit 0
fi

published="$(printf '%s\n' "$raw" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true)"
newest="$(printf '%s\n%s\n' "$version" "$published" | sort -V | tail -n1)"

if [[ "$newest" = "$version" ]]; then
  echo true
else
  echo "::warning::${version} is older than the newest published tag (${newest}); leaving :latest where it is" >&2
  echo false
fi
