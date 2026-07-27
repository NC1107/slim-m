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
  awk -v pkg="  $1:" '$0 == pkg {found=1} found && /version:/ {gsub(/[" ]/, "", $2); print $2; exit}' "$LOCK"
}

# A digest pinned here against a different lockfile version is worse than no
# check at all, so refuse rather than fetch the wrong thing.
for pair in "sqlite3 $SQLITE3_VERSION" "drift $DRIFT_VERSION"; do
  set -- $pair
  actual=$(pinned "$1")
  if [ "$actual" != "$2" ]; then
    echo "error: pubspec.lock pins $1 $actual but this script expects $2." >&2
    echo "Update the version and sha256 in $0 in the same change." >&2
    exit 1
  fi
done

fetch() {
  local url=$1 out=$2 want=$3
  [ -f "$out" ] && [ "$(sha256sum "$out" | cut -d' ' -f1)" = "$want" ] && {
    echo "ok $out (cached)"; return; }
  curl -sSfL --max-time 120 "$url" -o "$out"
  local got
  got=$(sha256sum "$out" | cut -d' ' -f1)
  if [ "$got" != "$want" ]; then
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
