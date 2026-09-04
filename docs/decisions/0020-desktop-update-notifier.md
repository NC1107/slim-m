# 0020 - The desktop update notifier is install-format aware

Date: 2026-09-04
Status: accepted

## Context

The owner asked for a desktop auto-updater in the splash: check GitHub for a newer client release, offer it, and apply it - with boilerplate loading copy when there is nothing to do.
The client ships in several Linux formats (a portable tarball, an rpm, and a flatpak, built by `release.yml`/`desktop-clients.yml`), and the owner's own install is the rpm.

The naive "download the new build and replace ourselves" only works for some of those formats, and doing it for the others is either impossible or unsafe.
Research (AppImage update docs, Flatpak sandbox docs, the state of Flutter desktop updaters) settled the shape below.

## The constraint that shapes everything: how a format updates is not the app's choice

An app can only self-replace files it owns and can write.

- A portable tarball or an AppImage is a user-owned tree (or single file), so the app can download a verified new build and swap it in place, then relaunch. AppImage even standardizes this (embedded update-information plus zsync, via libappimageupdate), and its own golden rules apply: never download without consent, respect a system "do not self-update" flag, do not nag on first launch.
- A flatpak runs in a sandbox where `/app` and `/usr` are read-only; it cannot self-update at all. The correct path is `flatpak update`, which pulls from the remote it was installed from.
- An rpm or deb is root-owned; the app cannot replace it without privilege. The correct path is the system package manager (`dnf`/`apt`), which needs a signed repo.

So the same feature must do different things per format, and for two of the four (flatpak, rpm - the owner's own) the app must hand off to the system rather than self-apply.

The app therefore has to know how it was installed.
That is baked into each build artifact at package time (a `--dart-define`), authoritative, with runtime sniffing as a fallback and a cross-check: `$APPIMAGE` for an AppImage, `/.flatpak-info` plus `$FLATPAK_ID` for a flatpak, an executable path under `/usr` (optionally confirmed with `rpm -qf`/`dpkg -S`) for a package, and none of those for a portable tarball.

## The dependency: safe apply needs signed artifacts

Applying an update is a remote-code-execution surface: an updater that runs an unverified binary is the vulnerability.
Self-apply (tarball/AppImage) must verify a signature or checksum against the release before executing - and client-artifact signing is still an open item ("Optional GPG signing secret for Linux client checksums").
The package-manager handoff (rpm/flatpak) inherits the system's own verification, but needs a signed repo to exist.
So the *apply* step of every format is gated on infrastructure the owner controls.

## Decision: build the notifier now, gate the applier on that infrastructure

Phase 1 (this record's initial scope): detect the format, check GitHub during the splash for the latest `client-v*` release, and, when one is newer than the running build, notify in the splash with a format-appropriate action - open the release page for a tarball/AppImage, point at `flatpak update` for a flatpak, point at the package manager for an rpm/deb.
"Not now" launches the current client immediately; a check that fails, times out, or is rate-limited falls straight through to launching, never blocking startup; no update shows the boilerplate loading copy.
Nothing is downloaded or executed, so Phase 1 carries none of the signing dependency and none of the RCE surface.

Phase 2 (filed separately, owner-gated): true one-click self-apply for tarball/AppImage - download, cosign/GPG-verify, replace, relaunch behind a progress bar that survives the restart (which pulls in the parked second-splash-window work) - and a signed dnf/flatpak repo so the packaged formats update in place.
For the owner's own rpm, the finished feature updates *through dnf*, never by the app replacing root-owned files.

## What Phase 1 is not

No download, no execution of a fetched artifact, no privilege escalation.
The GitHub check is a best-effort, timeout-bounded, unauthenticated read that never blocks or fails startup.
The interactive splash prompt preserves `awaitBootstrapWithSplashFloor`'s floor contract: the floor is still a floor, the prompt is a separate wait the user dismisses.

## Open items for Phase 2 (owner)

- Client-artifact signing (the GPG/cosign checksum secret), without which no format may self-apply.
- A signed package repo (dnf, and a flatpak remote) so rpm/flatpak update in place rather than by hand.
- The second splash window, so download progress outlives the relaunch an install requires.
- Update channel (stable `client-v*` only), and whether to remember "skip this version".
