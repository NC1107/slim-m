#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
#
# The file-size budget from CLAUDE.md: 300 lines soft, 500 lines hard.
# Warns at 300 and fails at 500, over hand-authored source only. Files already
# past 500 are in scripts/file-budget-allow.txt at the count they were listed
# at, which this treats as their own ceiling.
# What is excluded and why, and why 300 does not fail, is in docs/ci.md.

set -euo pipefail

soft=300
hard=500

cd "$(git rev-parse --show-toplevel)"
allowfile=scripts/file-budget-allow.txt

declare -A ceiling=()
declare -A hit=()
while IFS= read -r line; do
  line=${line%%#*}
  read -r path max _ <<<"$line" || true
  [ -n "${path:-}" ] || continue
  if ! [[ ${max:-} =~ ^[0-9]+$ ]]; then
    echo "::error file=$allowfile::'$path' has no line-count ceiling; the format is '<path> <lines> # why'"
    exit 1
  fi
  ceiling["$path"]=$max
done <"$allowfile"

mapfile -t files < <(
  git ls-files -- \
    '*.rs' '*.dart' '*.py' '*.sh' '*.swift' '*.kt' '*.kts' '*.js' \
    '*.sql' '*.yml' '*.yaml' '*.toml' '*.cc' '*.h' '*.gradle' |
    grep -v '^node_modules/' |
    grep -v '^\.sqlx/' |
    grep -Ev '\.(g|freezed|pb|pbenum|pbjson|pbserver)\.dart$' |
    sort
)

fail=0
soft_count=0
hard_count=0

for f in "${files[@]}"; do
  n=$(wc -l <"$f")
  limit=${ceiling[$f]:-}
  if [ -n "$limit" ]; then
    hit["$f"]=$n
    if [ "$n" -gt "$limit" ]; then
      echo "::error file=$f::$n lines, past the $limit it was allowlisted at; split it rather than raising the entry"
      fail=1
    fi
    continue
  fi
  if [ "$n" -gt "$hard" ]; then
    echo "::error file=$f::$n lines, over the ${hard}-line hard limit; split it in this change"
    hard_count=$((hard_count + 1))
    fail=1
  elif [ "$n" -gt "$soft" ]; then
    echo "::warning file=$f::$n lines, over the ${soft}-line review budget; split it before it grows again"
    soft_count=$((soft_count + 1))
  fi
done

for f in "${!ceiling[@]}"; do
  n=${hit[$f]:-}
  if [ -z "$n" ]; then
    echo "::error file=$allowfile::$f is allowlisted but is not a checked source file any more; remove the entry"
    fail=1
  elif [ "$n" -le "$hard" ]; then
    echo "::error file=$allowfile::$f is down to $n lines and no longer needs an entry; remove it"
    fail=1
  fi
done

echo "file budget: ${#files[@]} files checked, $soft_count over $soft, $hard_count over $hard, ${#ceiling[@]} allowlisted"
exit $fail
