// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The one file that touches Flutter's experimental windowing API.
///
/// Everything else in the app sees [PopOutWindowHandle], so a breaking change
/// in the framework's `_window.dart` lands here and nowhere else. The API only
/// works when the Linux build injects the `windowing` feature flag; see
/// `linux/flutter/CMakeLists.txt` and docs/decisions/0040.
library;

// ignore_for_file: invalid_use_of_internal_member, implementation_imports

import 'package:flutter/foundation.dart' show VoidCallback, kIsWeb;
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/widgets.dart';
import 'package:slimm_platform/platform.dart' show isLinuxHost;

/// A native window whose content is built in the main engine's widget tree.
abstract interface class PopOutWindowHandle {
  /// The view to hand `ViewAnchor`, rendering [child] in this window.
  Widget host(Widget child);

  void destroy();
}

typedef PopOutWindowFactory =
    PopOutWindowHandle Function({
      required String title,
      required Size size,
      required VoidCallback onCloseRequested,
    });

/// Null wherever a pop-out cannot be offered: web, every platform whose build
/// does not carry the windowing flag, and a Linux build made without it.
PopOutWindowFactory? nativePopOutWindowFactory() {
  if (kIsWeb || !isLinuxHost || !isWindowingEnabled) return null;
  return _NativePopOutWindow.new;
}

const _minSize = Size(240, 160);

class _NativePopOutWindow
    with RegularWindowControllerDelegate
    implements PopOutWindowHandle {
  _NativePopOutWindow({
    required String title,
    required Size size,
    required this.onCloseRequested,
  }) {
    _controller = RegularWindowController(
      size: size,
      constraints: BoxConstraints(
        minWidth: _minSize.width,
        minHeight: _minSize.height,
      ),
      title: title,
      delegate: this,
    );
  }

  final VoidCallback onCloseRequested;
  late final RegularWindowController _controller;

  @override
  void onWindowCloseRequested(RegularWindowController controller) =>
      onCloseRequested();

  @override
  Widget host(Widget child) =>
      RegularWindow(controller: _controller, child: child);

  @override
  void destroy() => _controller.destroy();
}
