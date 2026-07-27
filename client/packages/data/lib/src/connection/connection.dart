// SPDX-License-Identifier: Apache-2.0
/// Picks the sqlite3 backend for the platform this build targets.
///
/// The two backends share no runtime: the native one reaches sqlite3 through
/// `dart:ffi`, the browser one through WebAssembly and `dart:js_interop`.
/// A conditional export is what keeps each out of the other's compile.
/// Merely importing the native opener is enough to fail a web build, because
/// the whole `dart:ffi` transitive graph gets compiled with it.
library;

export 'unsupported.dart'
    if (dart.library.ffi) 'native.dart'
    if (dart.library.js_interop) 'web.dart';
