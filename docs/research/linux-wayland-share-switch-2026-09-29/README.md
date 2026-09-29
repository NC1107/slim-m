# Linux/Wayland: switching the shared screen mid-call

Owner's report: after choosing a screen to share, clicking share again always goes back to the screen chosen first.

## Cause

flutter_webrtc 1.6.0 keeps one `RTCDesktopMediaList` per source type in `FlutterScreenCapture::medialist_` (`common/cpp/src/flutter_screen_capture.cc`) for the life of the process.
`BuildDesktopSourcesList` only creates a list when none is cached, so the xdg-desktop-portal session, and the screen picked in it, is made once and reused by every later `getSources` and `getDisplayMedia`.
Stopping and restarting a share does not touch that cache.
The app-level "stop, then start again" route (PR #1180's hold-to-change) therefore cannot re-prompt the portal on its own.

This was found by reading the pinned source.
The portal picker cannot be driven non-interactively, so the failure was not reproduced on a live Wayland session, and neither was the fix.

## Upstream status

flutter_webrtc 1.6.1, 1.6.2 and 1.6.2+hotfix.1 to +hotfix.3 (up to 2026-09) do not change this file's caching, per the changelog.
A version bump is therefore not a fix.

## What ships in the app

`WebrtcDesktopSources.list()` on Linux first calls the plugin method `resetDesktopSources` on the `FlutterWebRTC.Method` channel, then enumerates as before.
Against an unpatched plugin the call throws `MissingPluginException`, which is swallowed, so behaviour is unchanged until the plugin is patched.

## The plugin patch

`reset-desktop-sources.patch` adds `resetDesktopSources`, which clears `medialist_` and `sources_`.
It applies with `patch -p1` from the root of a flutter_webrtc 1.6.0 checkout and touches three files under `common/cpp`.
It is not yet compiled or run against libwebrtc, only checked to apply cleanly.

## Owner steps to carry it as a git dependency

1. Fork `flutter-webrtc/flutter-webrtc` on GitHub.
2. Branch from the `v1.6.0` tag and apply the patch: `patch -p1 < reset-desktop-sources.patch`, then commit it.
3. Push the branch and note the commit SHA.
4. In `client/packages/rtc/pubspec.yaml` replace `flutter_webrtc: ^1.6.0` with a `git:` dependency (`url` of the fork, `ref` the SHA).
5. Run `flutter pub get` (without `--enforce-lockfile`) so the lockfile records it, and confirm livekit_client 2.10.0 still resolves.
6. Run `flutter build linux` and, on the Fedora KDE Wayland box, share a screen, hold the share button, and check the portal picker returns and peers see the new screen.
7. Optionally offer the same patch upstream.
