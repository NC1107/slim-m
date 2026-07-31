# slim-m desktop client (portable Linux build)

This is the Flutter bundle exactly as the release pipeline builds it: the app, its plugins, the Flutter engine and the WebRTC library, plus the asset tree under `data/`.
Nothing here needs installing.

```bash
./slimm_app
```

The runner locates `data/` and `lib/` relative to its own path, so the directory has to stay together, but it can live anywhere and it can be moved.

## What it needs from the system

GTK 3, and the usual desktop graphics stack, come from your distribution.
Four libraries are opened by name at runtime rather than linked, so a missing one fails only when you reach the feature rather than at startup:

| Library | Missing means |
|---|---|
| `libGL.so.1`, `libEGL.so.1` | the window never renders |
| `libpulse.so.0`, `libasound.so.2` | no microphone or speaker in a call |
| `libpipewire-0.3.so.0` | no screen share |
| `libsecret-1.so.0` | this one is linked, so the app will not start without it |

Screen share also needs `xdg-desktop-portal` running, and a remembered sign-in needs a Secret Service provider (gnome-keyring, KWallet, KeePassXC).

On Fedora, prefer the packaged build once it is available:

```
sudo dnf copr enable nc1107/slim-m
sudo dnf install slim-m-client
```

That wires all of the above as package dependencies and puts slim-m in the application launcher.
The COPR repository exists; the first package lands with the next tagged client release, so if `dnf install` finds nothing yet, this tarball is the current answer.

### Upgrading, and why a new release can look missing for two days

`sudo dnf upgrade slim-m-client` answering "Nothing to do" the day a release ships does not mean the repository is disabled or the build failed.

dnf caches repository metadata, and the COPR-generated `.repo` file sets no `metadata_expire`, so dnf's default of **48 hours** applies.
Until that lapses, dnf answers from a cache written before the new build existed and reports, correctly for what it knows, that there is nothing to do.

`sudo dnf copr enable nc1107/slim-m` appears to fix it, which is misleading: it rewrites the `.repo` file, and that invalidates the cache as a side effect.
The repository was enabled the whole time.

Ask for fresh metadata instead:

```
sudo dnf upgrade --refresh slim-m-client
```

Or, to stop having to remember the flag, tell dnf to check this one repository more often:

```
sudo dnf config-manager setopt copr:copr.fedorainfracloud.org:nc1107:slim-m.metadata_expire=1h
```

The cost of the shorter window is one small metadata fetch per hour of use, against a release being invisible for up to two days.
