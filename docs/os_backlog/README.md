<!-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 -->
# Per-platform backlog

Six files, one per supported OS: [windows_backlog.md](windows_backlog.md), [macos_backlog.md](macos_backlog.md), [linux_backlog.md](linux_backlog.md), [ios_backlog.md](ios_backlog.md), [android_backlog.md](android_backlog.md), [web_backlog.md](web_backlog.md).
Each collects the platform-specific issues this project already knows about, or reasonably expects, for that OS.
Added 2026-08-04 at the owner's request, after a run of real-device findings (the volume-slider platform split, the iOS broadcast-extension saga, the Wayland segfault) kept surfacing as scattered dated entries in `CLAUDE.md` with no single place naming, per platform, what to check before trusting a build on it.

## Why this exists alongside two other backlog files

`docs/BACKLOG.md` is the **feature** backlog: accepted extras, architectural hooks worth preserving, and features declined on purpose.
It answers "should we build X".

`docs/OPEN-QUESTIONS.md` is the **owner-decision** backlog: things an autonomous run could not settle without a person, an account, or a piece of hardware only the owner holds.
It answers "who has to decide, or press the button".

This directory is neither.
It answers a narrower question: **for this specific operating system, what already breaks, degrades, or is simply unbuilt, and how do we know?**
It is grounded in code and CI as they exist today, not in a feature request or a pending decision.
Where an entry here also has an owner-decision or feature angle, it says so and points at the other file rather than forking a second copy of the same fact.

## The evidence standard

The owner asked for what is *known*, and this project's own documentation culture (see `CLAUDE.md`, repeatedly) is explicit that a stale or invented entry costs more than a missing one: it sends the next contributor at a problem that does not exist, and gets copied forward into later documents as though still live.
So every file here is split into two sections.

**Confirmed.** Something read directly from source (a file and line), observed on a real device or a real CI run, or reproduced locally in this environment.
Every confirmed entry cites what established it: a file path, a `CLAUDE.md` section by name, a decision record, a PR or issue number, or a specific observed error string.

**Suspected.** A reasonable expectation that follows from confirmed facts but has not itself been run, built, or observed - typically because the platform in question has no scaffolded target in this repository, or because nobody here has the hardware.
Every suspected entry says what it is inferred from and what would turn it into a confirmed one.

Nothing sits in the confirmed list on the strength of "this is how it usually works."
If a claim could not be verified and could not be traced to a specific piece of existing evidence, it was left out rather than guessed at.

## How an entry is written

Each entry says what breaks (or would break), how it is known, and what it implies for whoever picks the platform up next - not just the symptom, but the action.
Where an entry is a rule that prevents a mistake from recurring rather than a live bug to fix, it is written as a rule, in the imperative, so it reads the same way the durable rules already scattered through `CLAUDE.md` do (for example: "never write a category on a class resolved through `NSClassFromString`").
Within each section, entries that would block a first build or a first successful run come before polish.

## Keeping these current

Treat these the way `CLAUDE.md` treats its own dated entries: when something here is fixed, do not delete the line, strike it through and say when and how, the same convention `CLAUDE.md` and `docs/ROADMAP.md` already use.
A struck-through entry is what stops the next reader re-finding a problem that no longer exists; a silently deleted one leaves no trace that the check was ever done.
When a platform gains real evidence (a scaffolded target, a real device run, a CI job), move the relevant suspected entries to confirmed, or close them, rather than leaving both a suspected and a confirmed version of the same fact.

## Where else to look

`docs/ROADMAP.md` carries the phase-by-phase exit criteria and status, including which platforms each phase's testing actually covered.
`docs/OPEN-QUESTIONS.md` sections 1 and 2 cover the device-confirmation gaps (iOS screen share, CallKit background execution, camera pre-toggle, the whole Android call path) that this directory's iOS and Android files also reference rather than duplicate.
`docs/research/background-blur-spike.md` is the single richest source for the Linux/Windows/macOS camera-blur gap and is cited directly from several files here rather than re-explained.
`docs/dependencies.md`'s "Client holds" section explains the `win32` package-version coupling that shapes the dependency tree on every platform, including ones nothing here builds for yet.
