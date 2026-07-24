// SPDX-License-Identifier: Apache-2.0
import 'package:flutter/widgets.dart';

/// Central icon access for slim-m interface chrome.
///
/// The UI uses the Lucide icon set and never emoji as chrome; CI fails on emoji
/// codepoints in client source. This wrapper is the single seam through which
/// the Lucide package is bound, so swapping or extending the icon set touches
/// one file. The concrete Lucide bindings are wired when the client is built on
/// a Flutter toolchain; until then this exposes the icon vocabulary the app
/// depends on.
abstract final class AppIcons {
  // Navigation and chrome.
  static const IconData hash = _placeholder;
  static const IconData voice = _placeholder;
  static const IconData settings = _placeholder;
  static const IconData members = _placeholder;

  // Calls and canvas.
  static const IconData mic = _placeholder;
  static const IconData camera = _placeholder;
  static const IconData screenShare = _placeholder;
  static const IconData leaveCall = _placeholder;
  static const IconData canvas = _placeholder;

  static const IconData _placeholder =
      IconData(0x2610, fontFamily: 'MaterialIcons');
}
