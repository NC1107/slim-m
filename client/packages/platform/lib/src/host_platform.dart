// SPDX-License-Identifier: Apache-2.0
/// Which operating system this build is running on, safe to ask from a
/// browser.
///
/// `dart:io` compiles on Flutter web, but every `Platform` getter is a stub
/// that throws `UnsupportedError`. A bare `Platform.isAndroid` therefore does
/// not answer "no" in a browser, it takes the whole app down before the first
/// frame. Every read short-circuits on [kIsWeb] first, which dart2js folds to
/// a constant, so the `dart:io` stub is never reached in a web build.
///
/// A browser on a phone is deliberately still false here. These answer "can
/// this build reach that OS's native APIs", not "what hardware is this", and
/// Safari on an iPhone has no APNs channel to bridge.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// True only for a native iOS build.
bool get isIOSHost => !kIsWeb && Platform.isIOS;

/// True only for a native Android build.
bool get isAndroidHost => !kIsWeb && Platform.isAndroid;

/// True only for a native Linux desktop build.
bool get isLinuxHost => !kIsWeb && Platform.isLinux;

/// True only for a native macOS build.
bool get isMacOSHost => !kIsWeb && Platform.isMacOS;

/// True only for a native Windows build.
bool get isWindowsHost => !kIsWeb && Platform.isWindows;

/// Any of the three desktop targets, native builds only. A browser on a
/// laptop is deliberately still false: this answers "does this build own a
/// window it can move, resize and hide", and a tab in a browser owns none of
/// that regardless of the hardware underneath it.
bool get isDesktopHost => isLinuxHost || isMacOSHost || isWindowsHost;

/// A short, human-recognisable name for this device, sent as `device_name`
/// on sign-in and registration so the Devices list in settings can tell one
/// session from another - the reason to revoke a session you don't recognise
/// is gone the moment every row reads alike.
///
/// Reads [defaultTargetPlatform] rather than [Platform]: it answers on web
/// too, where `dart:io`'s stub would throw exactly as it does for
/// [isIOSHost] above.
/// The host name is folded in only where this build can read one without
/// throwing, and that is the only thing added: no serial, build fingerprint,
/// or user agent, nothing past what tells two rows apart.
String get deviceDisplayName {
  final platform = switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.android => 'Android',
    TargetPlatform.macOS => 'Mac',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
  final host = kIsWeb ? null : _hostNameOrNull();
  return host == null ? platform : '$platform ($host)';
}

/// `Platform.localHostname` is unsupported on some embedders; a name this
/// build cannot read is worth losing, not worth crashing sign-in over.
String? _hostNameOrNull() {
  try {
    final name = Platform.localHostname.trim();
    return name.isEmpty ? null : name;
  } catch (_) {
    return null;
  }
}
