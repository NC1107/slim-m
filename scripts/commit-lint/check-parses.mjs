// SPDX-License-Identifier: Apache-2.0

/**
 * Gate: catch a commit body that crashes release-please's real parser,
 * without also failing a PR over an individual commit's subject line
 * simply not being a conventional commit - which, under squash-merge, is
 * normal and harmless.
 *
 * release-please reads the squash commit's message, not the PR title alone
 * (see CLAUDE.md's note on this, which this gate exists because that note
 * turned out to be incomplete). It parses that message with
 * `@conventional-commits/parser`, pinned here to the exact version
 * `googleapis/release-please-action`'s pinned commit
 * (5c625bfb5d1ff62eadeeb3772007f7f66fdcf071, tag v4.4.1) resolves:
 * release-please 17.3.0, which depends on
 * `@conventional-commits/parser@^0.4.1` and, as of this writing, resolves
 * that to 0.4.1, the only 0.4.x release published. package-lock.json in
 * this directory pins the exact resolved version and its integrity hash, so
 * a floating install cannot silently drift this gate away from the real
 * parser.
 *
 * The real distinction, found by reading `lib/parser.js` rather than by
 * pattern-matching the error text: the top-level `message()` production
 * parses its first line as `<summary>` (a strict `type ["(" scope ")"]
 * [!] ":" text` grammar) and `throw`s outright if that production fails.
 * Every line after it is `<body>`, whose footer-detection scan
 * (`preFooter`/`footer`/`token`) is deliberately forgiving: a candidate
 * footer that does not fully form just returns an `Error` value and the
 * scanner falls back to treating the line as plain text - except for one
 * production with no such fallback. `scope()` throws unconditionally, with
 * nothing above it in the call chain catching it, whenever a `(` is opened
 * and never closed before a newline or another `(`. That is the one
 * genuine crash: it fires from *body* text, at any position, is fatal to
 * the whole parse, and is what silently drops a real commit from
 * release-please's changelog (reproduced directly against real merged
 * history, PR #443 commit 7eebab8).
 *
 * A PR title is checked against the strict top-level grammar, because it
 * really does occupy that position: GitHub composes a squash commit's
 * message as the PR title, then each commit's own message as a "* "
 * -prefixed bullet, then a deduplicated trailer block (confirmed against
 * two real merged commits, 7eebab8 and 58b9d5a). The title is the one line
 * that production ever sees, so a title that fails this parse would throw
 * in the real squash too, silently dropping the whole PR from the
 * changelog - not merely miscategorising it.
 *
 * An individual commit is never checked against that same strict grammar,
 * because under squash-merge its own subject line never occupies that
 * position - it becomes a body bullet, not the summary, and an ordinary
 * non-conventional bullet parses there with no error at all (traced and
 * confirmed: `type()` grabs the first word, `scope()` and `separator()`
 * both abort gracefully with no throw, so `footer()` just returns an
 * `Error` and `body()` falls through to treating the line as text). What
 * an individual commit *is* checked against is the one production that
 * cannot recover: its full message is parsed as body text, under a fixed
 * synthetic `chore: placeholder` summary line standing in for whatever the
 * real PR title will be, so `scope()`'s unrecoverable throw is exercised
 * exactly as it would be in the real squash, with nothing else disturbed.
 * Verified directly against PR #460's own history: 7eebab8's offending
 * commit still throws this way (identical cause, position shifted by the
 * two synthetic lines); the two ordinary, non-conventional commits that
 * gate wrongly failed on (95fb2d5, 732c0c8) now parse cleanly, because
 * body-context scanning was always going to accept them - only testing
 * them out of context, forced through the strict summary grammar, made
 * them look broken.
 *
 * What this deliberately does not do: warn on an individual commit's own
 * subject not being conventional. Squash-merge already discards that
 * subject's standing as a changelog entry in its own right - it is bullet
 * prose under the PR title, nothing reads its "type" unless it happens to
 * *also* be footer-shaped, which is an opt-in bonus, not a requirement.
 * Warning on it would be noise pointing at a non-problem, the same shape
 * of over-strictness this gate was just found producing as a hard failure.
 *
 * What this still structurally cannot see: a hand-edit made during the
 * actual merge, when the person confirming the squash rewrites the
 * composed message. Nothing that runs before that moment can know what
 * they typed; that gap is inherent to squash-merge on GitHub.
 */

import { execFileSync } from 'node:child_process'
import { parser } from '@conventional-commits/parser'

const CRASH_PROBE_PREFIX = 'chore: placeholder\n\n'
const CRASH_PROBE_PREFIX_LINES = 2

function commitShas(baseSha, headSha) {
  const out = execFileSync(
    'git', ['log', '--no-merges', '--reverse', '--format=%H', `${baseSha}..${headSha}`],
    { encoding: 'utf8' },
  )
  return out.split('\n').filter((line) => line.length > 0)
}

function commitMessage(sha) {
  return execFileSync('git', ['log', '-1', '--format=%B', sha], { encoding: 'utf8' })
}

function tryParse(text) {
  try {
    parser(text)
    return null
  } catch (err) {
    return err
  }
}

function shiftReportedLine(message, lines) {
  return message.replace(/at (\d+):(\d+)/, (whole, line, col) => {
    const shifted = Number(line) - lines
    return shifted > 0 ? `at ${shifted}:${col}` : whole
  })
}

function checkTitle(title) {
  const err = tryParse(title)
  return err ? `PR title: ${err.message}` : null
}

function checkCommitCrashRisk(label, message) {
  const err = tryParse(CRASH_PROBE_PREFIX + message)
  if (!err) return null
  return `${label}: ${shiftReportedLine(err.message, CRASH_PROBE_PREFIX_LINES)}`
}

function main() {
  const title = process.env.PR_TITLE
  const baseSha = process.env.BASE_SHA
  const headSha = process.env.HEAD_SHA
  if (!title || !baseSha || !headSha) {
    console.error('PR_TITLE, BASE_SHA and HEAD_SHA must all be set')
    process.exit(2)
  }

  const shas = commitShas(baseSha, headSha)
  const failures = []
  const titleFailure = checkTitle(title)
  if (titleFailure) failures.push(titleFailure)

  for (const sha of shas) {
    const message = commitMessage(sha)
    const subject = message.split('\n', 1)[0]
    const failure = checkCommitCrashRisk(`${sha.slice(0, 7)} "${subject}"`, message)
    if (failure) failures.push(failure)
  }

  if (failures.length > 0) {
    // One line each; the full reasoning lives in this file's own doc comment.
    console.error('release-please cannot parse the following, and would silently drop them from the changelog:')
    for (const failure of failures) console.error(`  - ${failure}`)
    console.error('')
    console.error('Reword the offending line (often a code fragment with nested or unbalanced parens right after a blank line) so it does not read as a malformed conventional-commit footer.')
    process.exit(1)
  }

  console.log(`commit message parse: PR title parses cleanly, and ${shas.length} commit(s) carry no parser-crashing line`)
}

main()
