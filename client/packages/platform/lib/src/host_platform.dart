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

import 'package:flutter/foundation.dart' show kIsWeb;

/// True only for a native iOS build.
bool get isIOSHost => !kIsWeb && Platform.isIOS;

/// True only for a native Android build.
bool get isAndroidHost => !kIsWeb && Platform.isAndroid;
