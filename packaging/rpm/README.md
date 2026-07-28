# The rpm spec

`slim-m-client.spec` packages the slim-m desktop client for Fedora.
It repackages the portable release tarball rather than building from source, because a Flutter build needs the network for `pub` and a COPR/mock buildroot has none.

Installing it, cutting a COPR build, and creating the COPR project are in [`../fedora/README.md`](../fedora/README.md).
This file is about the spec itself: what shape the payload is, what it changes about it, and what `rpmlint` says.

## Layout

The payload is a directory tree, not a single binary.
Flutter ships its own engine (`libflutter_linux_gtk.so`), the compiled app (`libapp.so`), a plugin `.so` per Dart package that needs one, a 24 MB `libwebrtc.so`, and an asset tree under `data/`.

All of it is private to this app, so it goes in `%{_libdir}/slim-m-client`, which is `/usr/lib64/slim-m-client` on x86_64 and is where Fedora puts arch-specific files a package does not share.
`/usr/bin/slim-m` is a relative symlink into it.

A symlink works, rather than a wrapper script, because the runner locates `data/` and `lib/` by reading `/proc/self/exe`, which reports the link's target rather than the link.

## What the spec changes about the payload, and why

Two things, both fixing defects in what Flutter emits:

- **RUNPATH.** Flutter links four of the plugin `.so` files against absolute paths inside the build tree, one of them through a `..` across a symlink: `flutter_secure_storage_linux`, `flutter_webrtc`, `livekit_client` and `sqlite3_flutter_libs`. The `%install` loop rewrites all seven `lib/*.so`, so the three that were already clean gain an explicit `$ORIGIN` rather than being left implicit. `check-rpaths` fails the build over it, correctly: those paths only resolve on the machine that built the bundle, and anywhere else they are a search path pointing at whatever happens to sit there. `patchelf` rewrites each to `$ORIGIN`, which is all any of them ever needed. Without this, `liblivekit_client_plugin.so` finds its sibling only by the accident that the main binary has already loaded it under the same soname.
- **Permissions.** Flutter writes its shared objects `0644`; they are installed `0755`.

Nothing else is touched.
In particular the binaries are not stripped: there is no debuginfo subpackage to feed, since `%global debug_package %{nil}` is set for a prebuilt payload, and stripping `libapp.so` means stripping a Dart AOT snapshot for no gain.

## Runtime dependencies

The linked sonames come from rpm's ELF scan for free, so the spec declares only the libraries opened by name at runtime, which that scan cannot see:

| Declared | Opened by | Evidence |
|---|---|---|
| `libEGL.so.1`, `libGL.so.1` | `libepoxy`, which GTK links | both sonames appear in `libepoxy.so.0`, which imports `dlopen` and links neither |
| `libpulse.so.0`, `libasound.so.2` | `libwebrtc`'s audio device module | the two sonames sit adjacent in `libwebrtc.so`, next to `AudioDeviceBufferTimer` |
| `libpipewire-0.3.so.0` | `libwebrtc`'s screencast path | same file, immediately beside `org.freedesktop.portal.Desktop` |

`xdg-desktop-portal` and `gnome-keyring` are `Recommends`, not `Requires`.
They are services rather than libraries, each backs one feature rather than the app, and the Secret Service the client needs has several providers - KWallet and KeePassXC among them - with no virtual `Provides` shared between them to require instead.

The private `.so` files are kept out of rpm's dependency namespace in both directions, through `__provides_exclude_from` and `__requires_exclude`, so the package neither advertises `libwebrtc.so` to the distribution nor tries to resolve it there.

## Icons

The package installs the "Off-grid" mark into the hicolor theme at nine sizes, plus the SVG at `scalable/apps`.
The sizes are 16, 22, 24, 32, 48, 64, 128, 256 and 512, chosen by counting what is actually installed under `/usr/share/icons/hicolor/*/apps` on a Fedora KDE desktop rather than from a default list.

Every file is named `top.npcserver.slimm`, matching the `.desktop` file's `Icon=` line exactly.
That match is the whole thing: a mismatch shows as a generic placeholder in the launcher, and nothing warns about it.

The PNGs are not drawn by hand or checked in from a designer.
`client/packages/design_system/brand/generate.sh` rasterises them from `icon-master.svg`, the same master the iOS, Android and web icons come from, into `packaging/linux/icons/`.
Rerun it after changing a master or an accent token.

Each size is rendered natively from the vector at that size rather than downsampled from the 512.
Downsampling a tile this simple with Lanczos rings visibly: dark halos around the dots and a bright core in the square, worst exactly where it matters, at 16 and 22.

They are declared as individual `SourceN` lines with the size in the basename.
Both are forced: rpm flattens every source into one directory, so the basenames have to differ, and only sources the spec names travel inside the SRPM that the COPR job builds.

There is no `gtk-update-icon-cache` scriptlet.
Fedora's `filesystem` package carries a file trigger on that directory and rebuilds the cache itself.

The `.desktop` file is itself named for the GTK application id in `client/packages/app/linux/CMakeLists.txt`.
Wayland matches a window to its launcher entry by that id, so the two names have to agree.

## rpmlint findings left in place

`rpmlint` is not clean, and what remains is upstream payload or a check that does not fit this shape.
Each was checked rather than waved through:

- `crypto-policy-non-compliance-openssl` on `lib/libwebrtc.so` - upstream libwebrtc calls `SSL_CTX_set_cipher_list`, which pins a cipher list instead of deferring to the system crypto policy. It is inside a prebuilt vendored library, so nothing in this spec can change it; fixing it means an upstream change in libwebrtc or in flutter_webrtc's bundled build. Recorded rather than suppressed, because it is a real property of what we ship.
- `invalid-license Apache-2.0` - a false positive from a non-Fedora rpmlint. The PyPI build ships an empty `ValidLicenses` list, so every license string fails it, `GPL-3.0-only` in `nc1107/sink` included. Fedora's rpmlint reads the real list from `fedora-license-data`.
- `non-versioned-file-in-library-package` (6) - rpmlint infers "library package" from `.so` files under `%{_libdir}`. This is an application whose private libraries live in `%{_libdir}/%{name}`, which is the layout Fedora asks for.
- `invalid-soname`, `no-soname`, `missing-hash-section`, `missing-gnu-hash-section` - how upstream builds the engine and `libwebrtc`. Confirmed byte-identical in the unpackaged bundle, so `patchelf` did not introduce them, and harmless for libraries excluded from rpm's dependency namespace.
- `unstripped-binary-or-object` (6), `position-independent-executable-suggested` - deliberate, see above.
- `cross-directory-hard-link` - rpm's own payload dedup, not a link in the source. Flutter ships one 45-byte manifest at two paths with identical bytes, and both land inside `%{_libdir}/%{name}`, so they cannot straddle a filesystem.
- `no-signature` - COPR signs its own builds.
- `no-packager-tag`, `no-group-tag`, `no-buildroot-tag` - Fedora packages do not set `Packager` or `Group`, and `BuildRoot` has been obsolete since rpm 4.6.
- `no-manual-page-for-binary` - it is a GUI application.
- `incoherent-version-in-changelog` - the changelog entry omits `%{?dist}`, as Fedora changelog entries conventionally do.
