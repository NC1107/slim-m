# Job file template

One task, one agent, one branch, one PR.
A job file is the whole contract an agent works from: copy this template to `.claude/jobs/<job-id>.md` (untracked), fill every section, and hand the agent nothing else.
The agent executes the job exactly, takes it to an open PR with green CI, reports, and stops.
The orchestrator reviews and merges later, in a separate pass, on the owner's say-so - never the job agent.

Job ids are short kebab slugs (`fix-dock-size`, `canvas-portrait`) and are reused verbatim as the branch name and the worktree directory.

---

## Mission

What to build or fix, in three to six sentences.
State the acceptance criteria as observable behavior, not implementation: what a user or a test can see when this is done.
If the job is a bug fix, name the reproduction first; the fix starts by reproducing, per `CLAUDE.md`.

## Scope

The files and areas this job owns.
Name anything a sibling job owns as an explicit "do not touch".
Jobs are scoped to disjoint file sets; a genuine collision between two tasks means they should have been one job, or sequential ones - stop and report rather than improvising across the boundary.

## Where to work

- `git worktree add .claude/worktrees/<job-id> -b <job-id> origin/main` from the repo root, and do everything inside that worktree.
- Run `flutter pub get` in the worktree's `client/` before trusting any analyzer output: a fresh worktree reports walls of unresolved-package errors that are resolution, not compilation, and the tell is that they name imports rather than anything you wrote.
- Never build, test, or run anything that takes more than a few seconds in the shared top-level checkout; other agents work there concurrently and a reset under a running build corrupts it.
- Never open desktop app windows (`flutter run -d linux` is forbidden); this box is the owner's own desktop.
- Temporary files go in your session scratchpad, never in the repo or `/tmp` directly.

## Rules

Read the repo's `CLAUDE.md` before starting; it is the authority and this checklist is only the operational digest.

- Commits: `git commit -s` (DCO sign-off), never any AI attribution or co-author trailer, anywhere, even where a platform default says to add one.
- Never the em dash character; a plain dash. In long markdown, each sentence on its own line.
- Plain `//` and `#` comments are capped at one line; a longer why belongs in a doc comment or `docs/`.
- Stage deliberately: `git add` the files you intend, never `git add -A` blind.
- Gates before every commit, run so a failure actually fails (never piped through `tail`, which eats the exit code):
  `bash scripts/check-comment-cap.sh && bash scripts/check-file-budget.sh && python3 scripts/check-error-surface.py`
- Client changes: `dart format` clean, `dart analyze` with zero new warnings (pre-existing infos are tolerated, new ones are not), and `flutter test` run from the owning package's own root, never from `client/`.
- Server changes: `SQLX_OFFLINE=true cargo fmt --all --check`, `clippy --all-targets --all-features -- -D warnings`, `cargo test --all`.
  After changing any `query!` macro, regenerate the offline cache with `cargo sqlx prepare --workspace -- --all-targets` and treat an unexplained `.sqlx/` deletion in `git status` as a bug.
- Every load-bearing line gets mutation-tested: apply the mutation, confirm exactly the test written for it fails and nothing else, restore by hand (never `git checkout --`, which destroys uncommitted work), confirm the restore byte-identical.
- Routes changed means `schema/openapi.yaml` changed in the same commit, plus a `tests/response_contract` case.

## Deliverable

- Push the branch and open the PR with `npx -y gh-axi pr create --title "..." --body-file <path>`.
- The PR title is a conventional commit; release-please reads it, and a bad title silently corrupts the changelog.
- The PR body is published under the owner's name: read `~/.claude/Voice.md` first and write in that voice - plain, hedged, anti-hype, lowercase product names, no emoji, no exclamation points, walks through how the thing works.
- Watch CI (`npx -y gh-axi pr checks <n>` in an until-loop with a sleep) and fix your own red checks; done means every check green, not the PR merely existing.

## Stop condition

Report back and stop: the PR number, a one-paragraph summary, what was mutation-tested, and anything deliberately left open.
Never merge.
Never push to main.
Never post or react in the live instance's backlog channel; status reporting belongs to the orchestrator.

## If blocked

Report the blocker precisely - what was tried, what failed, the exact error - and stop.
Do not improvise outside the Scope section to get unblocked.
