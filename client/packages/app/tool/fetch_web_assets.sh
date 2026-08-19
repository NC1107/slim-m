#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Fetches the two binaries the web build needs, pinned to the versions in
# pubspec.lock and checked against a recorded digest.
#
# They are fetched rather than committed because the web build is a test
# surface rather than something shipped, so 355KB of vendored minified JS in
# git bought nothing and cost a linter finding on every line of it.
set -euo pipefail

cd "$(dirname "$0")/.."
LOCK=../../pubspec.lock
WEB=web

# Digests are the contract. A silently different worker talking to a client
# from another drift version fails at runtime in the browser, not at build.
SQLITE3_VERSION=2.9.4
SQLITE3_SHA=922a76b182b6af69b030c8e2fdd3283ecc8e827248b20e4b1f3f3db170b52117
DRIFT_VERSION=2.31.0
DRIFT_SHA=f0a9b87085f732fd7b6ee7eb34d3858c556f05d221eb1febfc443649cd365752

pinned() {
  local name=$1
  awk -v pkg="  $name:" '$0 == pkg {found=1} found && /version:/ {gsub(/[" ]/, "", $2); print $2; exit}' "$LOCK"
}

# A digest pinned here against a different lockfile version is worse than no
# check at all, so refuse rather than fetch the wrong thing.
check_pinned() {
  local pkg=$1 want=$2 actual
  actual=$(pinned "$pkg")
  if [[ "$actual" != "$want" ]]; then
    echo "error: pubspec.lock pins $pkg $actual but this script expects $want." >&2
    echo "Update the version and sha256 in $0 in the same change." >&2
    exit 1
  fi
}

check_pinned sqlite3 "$SQLITE3_VERSION"
check_pinned drift "$DRIFT_VERSION"

fetch() {
  local url=$1 out=$2 want=$3
  if [[ -f "$out" && "$(sha256sum "$out" | cut -d' ' -f1)" == "$want" ]]; then
    echo "ok $out (cached)"
    return
  fi
  # Retries cover the transient release-CDN 503 that killed three whole e2e
  # runs in a row on 2026-08-12 (issue #621) before a single scenario ran.
  curl -sSfL --max-time 120 --retry 5 --retry-delay 5 --retry-all-errors \
    "$url" -o "$out"
  local got
  got=$(sha256sum "$out" | cut -d' ' -f1)
  if [[ "$got" != "$want" ]]; then
    rm -f "$out"
    echo "error: $out digest mismatch. expected $want, got $got" >&2
    exit 1
  fi
  echo "ok $out"
}

mkdir -p "$WEB"
fetch "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-${SQLITE3_VERSION}/sqlite3.wasm" \
  "$WEB/sqlite3.wasm" "$SQLITE3_SHA"
fetch "https://github.com/simolus3/drift/releases/download/drift-${DRIFT_VERSION}/drift_worker.js" \
  "$WEB/drift_worker.js" "$DRIFT_SHA"
