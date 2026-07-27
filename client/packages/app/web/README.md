<!-- SPDX-License-Identifier: Apache-2.0 -->
# Web assets

The web build exists to drive this UI automatically.
Native Linux runs, but no synthetic input reaches it on a Wayland desktop, and a browser can be driven over the DevTools protocol.
It is a test surface, not a distribution target.

Two of the files the build needs are binaries rather than source. **Neither is committed.**
`tool/fetch_web_assets.sh` downloads both, refusing to run if the versions it pins have drifted from `client/pubspec.lock`, and checking each against a recorded sha256.

They are fetched rather than vendored because this is a test surface: 355KB of minified worker in git bought nothing and cost a static-analysis finding on every line of it.
Run the script before `flutter build web`; it is a no-op once the files are present and their digests match.

## `sqlite3.wasm`

sqlite3 compiled to WebAssembly, which is how drift reaches a database in a browser.
Downloaded from the sqlite3.dart release matching the `sqlite3` version in `pubspec.lock`:

```
curl -sSL -o web/sqlite3.wasm \
  https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-<version>/sqlite3.wasm
```

Currently sqlite3 2.9.4, carrying SQLite 3.50.4, sha256 `922a76b182b6af69b030c8e2fdd3283ecc8e827248b20e4b1f3f3db170b52117`.

## `drift_worker.js`

The worker drift runs the database in, so queries do not block the frame.
Downloaded from the drift release matching the `drift` version in `pubspec.lock`:

```
curl -sSL -o web/drift_worker.js \
  https://github.com/simolus3/drift/releases/download/drift-<version>/drift_worker.js
```

Currently drift 2.31.0, sha256 `f0a9b87085f732fd7b6ee7eb34d3858c556f05d221eb1febfc443649cd365752`.

Drift also exposes `WasmDatabase.workerMainForOpen`, so this file can be compiled from source with `dart compile js` instead of downloaded.
The published artifact is used because it is what the drift documentation points at, and because compiling it locally adds a build step nothing else in this repo needs.

## Refreshing them

Bumping `drift` or `sqlite3` means updating the version *and* the sha256 in `tool/fetch_web_assets.sh` in the same change; the script refuses to fetch against a lockfile it was not written for.

Both are read at runtime by `packages/data/lib/src/connection/web.dart`, by fixed name, from the app's own origin.
Bumping `drift` or `sqlite3` in `pubspec.yaml` means re-downloading the matching file here in the same change: a worker from one drift version talking to a client from another is not a supported combination, and the failure shows up as a runtime protocol error in the browser rather than a build failure.
