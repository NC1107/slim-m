<!-- SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0 -->
# Installing slim-m

How to get the slim-m app on your device.
This page is for people joining someone's space, not for running a server - that is [deploy/README.md](../deploy/README.md).

You will need two things from whoever runs the space: its **address**, and usually an **invite code**.
Ask them for both before you start.

## The short version

| You are on | Do this |
| --- | --- |
| Anything with a browser | Open the space's web address, if it has one. No install at all. |
| Fedora | `sudo dnf copr enable nc1107/slim-m` then `sudo dnf install slim-m-client` |
| Other Linux | The `.flatpak` or the `.tar.gz` from [Releases](https://github.com/NC1107/slim-m/releases/latest) |
| Windows | The `-windows-x64.zip` from [Releases](https://github.com/NC1107/slim-m/releases/latest) |
| macOS | The `-macos.zip` from [Releases](https://github.com/NC1107/slim-m/releases/latest) |
| Android | The `-android.apk` from [Releases](https://github.com/NC1107/slim-m/releases/latest) |
| iPhone or iPad | Ask the space's owner for a TestFlight invite |

## The browser, which needs no install

If the space runs the web client, open its address in any browser and sign in.
Nothing to download, nothing to update, and it works on a phone.

Whether a space offers this is up to whoever runs it, so ask.
If they say yes, this is the easiest way in by a wide margin and you can stop reading here.

## Fedora

There is a package repository, which means updates arrive through `dnf` like anything else on the system:

```bash
sudo dnf copr enable nc1107/slim-m
sudo dnf install slim-m-client
```

This pulls in the tray-icon and screen-share dependencies for you and puts slim-m in the application launcher.
It is the best desktop experience and the one to prefer if you are on Fedora.

One oddity worth knowing: `dnf upgrade` can answer "Nothing to do" for up to 48 hours after a release, because dnf caches repository metadata that long.
`sudo dnf upgrade --refresh slim-m-client` skips the cache.

## Other Linux

Two options from the [latest release](https://github.com/NC1107/slim-m/releases/latest).

**Flatpak**, if you have it:

```bash
flatpak install ./slim-m-client-<version>.flatpak
flatpak run top.npcserver.slimm
```

There is no flatpak remote yet, so `flatpak update` will not find new versions - you download the new bundle and install it over the old one.

**Tarball** (`-linux-amd64.tar.gz`): extract it and run the binary inside.
It needs `libayatana-appindicator3.so.1` for the tray icon and will not start without it, plus `xdg-desktop-portal` for screen share and a keyring (gnome-keyring, KWallet, KeePassXC) to stay signed in.
[packaging/linux/README.md](../packaging/linux/README.md) has the full dependency list.

## Windows

Download `slim-m-client-<version>-windows-x64.zip`, unzip it anywhere, and run the executable inside.

**Windows will try to stop you, and this is expected.**
There is no code-signing certificate for this project, so SmartScreen shows a blue box saying "Windows protected your PC" and "unrecognized app".
Its default button is **Don't run**, so you have to click **More info** first, then **Run anyway**.

That warning means Microsoft has not seen this app before, which is true.
If you would rather not click through it, use the browser instead.

## macOS

Download `slim-m-client-<version>-macos.zip` and unzip it.

**Do not double-click the app the first time.**
The build is ad-hoc signed rather than notarized, so Gatekeeper quarantines anything downloaded and a double-click gives you a dead end.
Instead **right-click the app and choose Open**, then confirm - that path offers an Open button where double-clicking does not.

If it still refuses, clear the quarantine flag directly:

```bash
xattr -d com.apple.quarantine /path/to/slim-m.app
```

You only have to do this once per download.

## Android

Download `slim-m-client-android.apk` and open it.

There is no Play Store listing, so this is a sideload and Android will warn you.
You will be asked to allow installs from whatever app you downloaded with (usually your browser), which means a trip into Settings the first time.

Download `slim-m-client-android.apk`.
Releases from 0.80.0 onward carry only the apk; older ones also list an `.aab`, which is a Play Store upload format and cannot be installed on a phone.

Android also has no in-app update prompt yet, so you will not be told when a new version exists - check the releases page now and then.

## iPhone and iPad

iOS builds go out through TestFlight, which needs the space owner to add your Apple ID first.
Ask them, accept the email invite, install TestFlight from the App Store, and slim-m appears inside it.

There is no way to sideload on iOS, so TestFlight is the only route.

## Signing in

However you installed it, the first run asks for the space's address and, if the space is invite-only, a code.
Both come from whoever runs it.

You will also see a **security check** the first time you connect to a space, showing eight groups of letters and numbers.
That is the server's fingerprint.
If you can, check it matches what the owner sees in their server log - it is how you know you reached their server and not somebody in between.
If you cannot, "It matches - continue" carries on.

Forgotten passwords are handled by the space's admin, not by email: they issue you a one-time reset code, and "Trouble signing in?" on the sign-in screen is where you spend it.

## Which file is which

A release page lists several files, and most of them are not for you:

| File | What it is |
| --- | --- |
| `slim-m-client-<version>-1.fc44.x86_64.rpm` | Fedora package, but prefer the `dnf copr` route above |
| `slim-m-client-<version>-linux-amd64.tar.gz` | Linux, extract and run |
| `slim-m-client-<version>.flatpak` | Linux flatpak bundle |
| `slim-m-client-<version>-windows-x64.zip` | Windows |
| `slim-m-client-<version>-macos.zip` | macOS |
| `slim-m-client-android.apk` | Android, this is the one you want |
| `SHA256SUMS`, `SHA256SUMS.android` | checksums, for verifying a download |

To check a download matches what was published, compare it against the checksums file:

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

---

**Running the beta rather than joining it?**
[`docs/BETA-TESTERS.md`](BETA-TESTERS.md) is what to tell a tester before they start, and what to ask them afterwards - including the four iOS paths and the Android call path that no real device has ever confirmed.
