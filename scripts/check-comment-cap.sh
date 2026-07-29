#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# The one-line comment cap from CLAUDE.md: a plain `//` or `#` comment never
# spans more than one line. Code explains how; a comment explains why, and one
# line is enough for a why. A reason that genuinely needs more room belongs in
# a doc comment on the item, in docs/, or in a decision record.
#
# Doc comments are exempt (`///`, `//!`, `/**`): they carry an item's contract
# to its callers and to `dart doc` / `cargo doc`, which is a different job.
# So is a `#` block at the very top of a YAML, TOML or shell file, which is
# that file's only documentation mechanism.
#
# Ratcheting, not a big-bang sweep: 174 runs across 68 files predate this gate
# (an audit counted them), so scripts/comment-cap-allow.txt holds each file's
# count at the time it was listed and this fails if a file exceeds its own
# number. Fixing a file lowers its entry; a file not listed must be clean.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
allowfile=scripts/comment-cap-allow.txt

declare -A ceiling=()
declare -A seen=()
if [[ -f $allowfile ]]; then
  while IFS= read -r line; do
    line=${line%%#*}
    read -r path max _ <<<"$line" || true
    [[ -n ${path:-} ]] || continue
    if ! [[ ${max:-} =~ ^[0-9]+$ ]]; then
      echo "::error file=$allowfile::'$path' has no run count; the format is '<path> <runs> # why'" >&2
      exit 1
    fi
    ceiling[$path]=$max
  done <"$allowfile"
fi

# Counts maximal runs of 2+ consecutive plain-comment lines in one file.
runs_in() {
  awk '
    # A plain comment is // not followed by /, or # not followed by !.
    /^[[:space:]]*\/\/[^\/]/ || /^[[:space:]]*\/\/$/ { streak++; next }
    /^[[:space:]]*#([^!]|$)/ { streak++; next }
    { if (streak > 1) runs++; streak = 0 }
    END { if (streak > 1) runs++; print runs + 0 }
  ' "$1"
}

status=0
checked=0
over=0

while IFS= read -r file; do
  case $file in
    *.g.dart | *.freezed.dart | .sqlx/* | */generated/*) continue ;;
  esac
  # Shell, YAML and TOML get a file-header exemption this counter cannot see,
  # so they are out of scope entirely rather than counted wrongly.
  case $file in
    *.sh | *.yml | *.yaml | *.toml) continue ;;
  esac
  checked=$((checked + 1))
  count=$(runs_in "$file")
  allowed=${ceiling[$file]:-0}
  seen[$file]=1
  if ((count > allowed)); then
    over=$((over + 1))
    status=1
    if ((allowed > 0)); then
      echo "::error file=$file::$count multi-line comment runs, over its recorded $allowed; compress the new one or move the why to a doc comment" >&2
    else
      echo "::error file=$file::$count multi-line comment run(s); a plain comment is capped at one line (a doc comment is not)" >&2
    fi
  fi
done < <(git ls-files '*.dart' '*.rs' '*.py')

# A file that dropped off the list entirely (deleted, or renamed) is not an
# error, but a stale entry is worth saying so the allowlist stays honest.
for path in "${!ceiling[@]}"; do
  [[ -n ${seen[$path]:-} ]] || echo "::warning file=$allowfile::'$path' is listed but no longer exists; drop the line"
done

echo "comment cap: $checked files checked, $over over their ceiling, ${#ceiling[@]} allowlisted"
exit $status
