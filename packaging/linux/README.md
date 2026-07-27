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
