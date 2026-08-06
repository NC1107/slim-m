// SPDX-License-Identifier: Apache-2.0

/**
 * Gate: every commit message a PR could contribute to a squash-merge commit
 * must survive the real parser release-please runs over it, not an
 * approximation of one.
 *
 * release-please reads the squash commit's message, not the PR title alone
 * (see CLAUDE.md's "The PR title is the only thing release-please reads"
 * note, which this gate exists because that note turned out to be
 * incomplete). It parses that message with `@conventional-commits/parser`,
 * pinned here to the exact version `googleapis/release-please-action`'s
 * pinned commit (5c625bfb5d1ff62eadeeb3772007f7f66fdcf071, tag v4.4.1)
 * resolves: release-please 17.3.0, which depends on
 * `@conventional-commits/parser@^0.4.1` and, as of this writing, resolves
 * that to 0.4.1, the only 0.4.x release published. package-lock.json in
 * this directory pins the exact resolved version and its integrity hash, so
 * a floating install cannot silently drift this gate away from the real
 * parser.
 *
 * What this checks, and what it structurally cannot: GitHub composes a
 * squash commit's message from the PR title and the individual commits
 * (title, then each commit's own message as a "* "-prefixed bullet, then a
 * deduplicated trailer block), and the person doing the merge can hand-edit
 * that composed text before confirming. Nothing running before the merge
 * can see the final byte-for-byte result. What this checks instead is
 * every commit that would feed that composition: the PR title (the summary
 * line, the only line no template ever wraps in a bullet) and each
 * commit's own full message, parsed standalone.
 *
 * That standalone check is not a guess at equivalence: reproduced directly
 * against real merged history (PR #443, commit 7eebab8) - the parser fails
 * at the exact same column (29) whether it reads the full composed squash
 * message or just the one individual commit carrying the offending line,
 * because the crash comes from a footer-detection attempt scanning body
 * text, which happens per physical line regardless of what a later commit
 * or a bullet prefix put around it. A bullet prefix and the trailer block
 * this script does not reconstruct both sit outside every commit's own
 * body text, so neither can hide a crash a standalone parse would have
 * caught - but a hand-edit made during the actual merge is outside what
 * any pre-merge check can see, by definition.
 */

import { execFileSync } from 'node:child_process'
import { parser } from '@conventional-commits/parser'

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

function tryParse(label, text) {
  try {
    parser(text)
    return null
  } catch (err) {
    return `${label}: ${err.message}`
  }
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
  const titleFailure = tryParse('PR title', title)
  if (titleFailure) failures.push(titleFailure)

  for (const sha of shas) {
    const message = commitMessage(sha)
    const subject = message.split('\n', 1)[0]
    const failure = tryParse(`${sha.slice(0, 7)} "${subject}"`, message)
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

  console.log(`commit message parse: PR title and ${shas.length} commit(s) all parse cleanly`)
}

main()
