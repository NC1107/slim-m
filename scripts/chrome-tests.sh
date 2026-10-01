#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
# Runs the files in client/chrome-tests.txt under dart2js, one flutter test per package.
set -euo pipefail
cd "$(dirname "$0")/../client"
status=0
mapfile -t packages < <(cut -d/ -f1 chrome-tests.txt | sort -u)
for pkg in "${packages[@]}"; do
  files=$(grep "^$pkg/" chrome-tests.txt | sed "s#^$pkg/##")
  echo "::group::flutter test --platform chrome - $pkg"
  # shellcheck disable=SC2086
  (cd "packages/$pkg" && flutter test --platform chrome --concurrency=4 $files) || status=$?
  echo "::endgroup::"
done
exit $status
