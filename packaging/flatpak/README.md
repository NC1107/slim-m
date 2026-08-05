# The flatpak manifest

`top.npcserver.slimm.yaml` packages the slim-m desktop client as a Flatpak.
It is the primary Linux artifact per `docs/ROADMAP.md`'s Phase 9 entry ("Flatpak primary, rpm alongside"), and the last half of a residual `CLAUDE.md` carried since 2026-07-28: the rpm half shipped that day, this half did not exist until now.

Like the rpm, it repackages the already-built Flutter Linux bundle rather than running `flutter build linux` inside the sandbox.
The sandbox has no network by default and `dart pub get` needs one.
So `release.yml`'s `linux-client` job builds the bundle first, and this manifest's `dir` source points straight at `client/packages/app/build/linux/x64/release/bundle`.

## What is verified, and how

This manifest has been built for real, twice, with `org.flatpak.Builder` (the sandboxed Flathub build tool, installed with `flatpak install --user flathub org.flatpak.Builder`) against a real `flutter build linux --release` output produced on this machine.
Both times it produced a working `flatpak-builder` export and an installable `.flatpak` bundle.
`flatpak install --user` accepted it, and the sandbox's own dynamic linker resolved every plugin library except one, below.
That is the extent of what was checked: **the app has never been launched from the resulting bundle.**
Nothing here proves the window opens, that a call connects, or that any permission below is sufficient rather than merely plausible.

Two real defects were found and fixed by this build, not by reading the manifest:

- **The app's own icon failed flatpak-builder's export-time icon check**, `... is not a valid icon: Format not recognized`.
  `packaging/linux/icons/top.npcserver.slimm.svg` opens with an SPDX/rationale comment before the `<svg>` tag, and gdk-pixbuf's SVG sniffer matches only `<svg` or `<!DOCTYPE svg` in the file's first bytes.
  It does not skip a leading comment to find the real tag.
  The manifest strips it at build time (`sed -n '/<svg/,$p'`) rather than editing the shared asset the rpm and every other icon size also read.
- **Four of the Flutter-built plugin `.so` files carry an absolute build-tree `RUNPATH`**, confirmed directly with `readelf -d`, the same defect the rpm's own README documents and fixes with `patchelf`.
  The Freedesktop SDK does not carry `patchelf` (checked with `find` inside `org.freedesktop.Sdk//25.08`, not assumed from the fact that some other flatpak used it), so the manifest fetches a pinned static release build of it from `NixOS/patchelf` on GitHub as a source used only during the build, never installed into `/app`.

## What is not verified, and the one real problem found doing this on this machine

**The app was never launched, on any display.**
No screenshot, no confirmation the GTK window paints, no confirmation a call connects, no confirmation the webcam or screen-share permissions below are the right shape rather than merely a documented pattern from another WebRTC flatpak app (Element's `im.riot.Riot.yaml`, fetched and read for this).

**A real, reproducible glibc mismatch was found, and it is very likely specific to building on this machine rather than to the manifest.**
Inside the installed bundle, `ldd /app/slim-m/lib/liblivekit_client_plugin.so` reports `GLIBC_2.43' not found`.
`org.freedesktop.Platform//25.08`'s own `libm.so.6` tops out at `GLIBC_2.42` (checked with `objdump -T` inside `org.freedesktop.Sdk//25.08`), while this machine's own glibc, which built the bundle, is 2.43.
A newer symbol version than the runtime ships leaked into the LiveKit plugin's link.
`release.yml`'s `linux-client` job builds on GitHub's `ubuntu-latest`, which as of this writing is Ubuntu 24.04 LTS at glibc 2.39, comfortably under the runtime's 2.42 ceiling, so this specific failure most likely does not reproduce there.
It is recorded rather than silently worked around because "most likely" is not "confirmed," and because it names a real, general risk: if a future CI runner image ever ships a newer glibc than whatever `runtime-version` this manifest is pinned to, the same failure would recur, silently, for whichever plugin happens to pull in the newest symbol.
Nothing here fixes that risk structurally.
The mitigation is watching the first real release build's job log for exactly this `ldd`/`GLIBC_` shape if voice ever fails to load from a shipped Flatpak.

**Not attempted**, each for a stated reason: Flathub submission (out of scope per the task this manifest was built under; a real submission also wants an AppStream `metainfo.xml`, which nothing here writes); a 32-bit or aarch64 build (the rpm's own `ExclusiveArch: x86_64` reasoning applies identically, since the bundle `linux-client` builds is x86_64 only); and confirming the `--talk-name=org.freedesktop.secrets` and `--filesystem=xdg-run/pipewire-0` grants are sufficient rather than merely necessary, which needs a running app on a session with a Secret Service provider and a compositor, not a build sandbox.

## Why `release.yml`'s flatpak step is `continue-on-error: true`

The rpm has shipped from dozens of real release runs; this manifest has zero.
A release job that fails outright on an unproven manifest is worse than the warn-and-skip this repository already uses for an absent packaging input, so the same shape is extended to a present-but-possibly-broken one: `steps.pkg.outputs.flatpak` still gates whether the step runs at all, and `continue-on-error: true` means a failure inside it cannot take down the portable tarball or the rpm the same job already produces.
The checksums step already tolerates a missing `.flatpak` (`shopt -s nullglob`), so this costs nothing on the success path and only changes behaviour the one way that matters: a broken flatpak build now shows as a yellow warning on an otherwise green release, not a red one.
Once a few real releases have produced a working bundle, revisit whether `continue-on-error` should come off.
The rpm needed no such guard once it had a track record.

## Permissions, briefly

The manifest's own inline comments carry the reasoning for each non-obvious `finish-args` entry.
The short version: `--device=all` is for the webcam (`flutter_webrtc`'s Linux capturer uses V4L2 directly, not the Camera portal, the same reason Element's own manifest grants it), `--talk-name=org.freedesktop.secrets` is for `flutter_secure_storage`'s libsecret backend (not portal-mediated), and `--filesystem=xdg-run/pipewire-0` pairs with the ScreenCast portal for screen share, again matching Element's own grant for the same feature shape.

## Reproducing this

```bash
flatpak install --user flathub org.flatpak.Builder
cd client/packages/app && flutter clean && dart pub get && flutter build linux --release && cd -
flatpak run --user --filesystem=host --share=network org.flatpak.Builder \
  --force-clean --repo=/tmp/slimm-flatpak-repo /tmp/slimm-flatpak-build \
  packaging/flatpak/top.npcserver.slimm.yaml
flatpak build-bundle /tmp/slimm-flatpak-repo /tmp/slim-m-client.flatpak top.npcserver.slimm
flatpak install --user /tmp/slim-m-client.flatpak
flatpak run top.npcserver.slimm   # the one step this account has not taken
```

`flutter clean` before `flutter build linux` is not optional if a previous `build/` was removed by hand rather than through `flutter clean`.
The CMake configuration under `linux/flutter/ephemeral` survives a bare `rm -rf build/` and then fails with `file INSTALL cannot find .../build/native_assets/linux`, since that directory no longer exists but the stale generated install script still expects it.
