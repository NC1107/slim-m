// SPDX-License-Identifier: Apache-2.0
/// A [DesktopWindowPort] with no window, no plugin channel, and no platform
/// behind it at all - shared across every desktop-shell test that needs one
/// rather than each rebuilding its own copy.
library;

import 'dart:async';

import 'package:slimm_app/src/desktop/desktop_window_port.dart';
import 'package:slimm_app/src/desktop/window_geometry.dart';

class FakeDesktopWindowPort implements DesktopWindowPort {
  final _controller = StreamController<DesktopWindowEventKind>.broadcast();

  bool maximized = false;
  bool fullScreen = false;
  bool visible = true;
  WindowRect bounds = const WindowRect(x: 10, y: 10, width: 1280, height: 720);

  int hideCalls = 0;
  int minimizeCalls = 0;
  int maximizeCalls = 0;
  int unmaximizeCalls = 0;
  int startDraggingCalls = 0;
  int destroyCalls = 0;
  int showCalls = 0;
  int restoreCalls = 0;

  void emit(DesktopWindowEventKind kind) => _controller.add(kind);

  @override
  Stream<DesktopWindowEventKind> get events => _controller.stream;

  @override
  Future<WindowRect> getBounds() async => bounds;
  @override
  Future<bool> isMaximized() async => maximized;
  @override
  Future<bool> isFullScreen() async => fullScreen;
  @override
  Future<void> hide() async => hideCalls++;
  @override
  Future<void> minimize() async => minimizeCalls++;
  @override
  Future<void> maximize() async {
    maximizeCalls++;
    maximized = true;
  }

  @override
  Future<void> unmaximize() async {
    unmaximizeCalls++;
    maximized = false;
  }

  @override
  Future<void> startDragging() async => startDraggingCalls++;
  @override
  Future<void> destroy() async => destroyCalls++;

  @override
  Future<void> ensureInitialized() async {}
  @override
  Future<void> setBounds(WindowRect rect) async {}
  @override
  Future<void> setSize(WindowSize size) async {}
  @override
  Future<void> center() async {}
  @override
  Future<void> setFullScreen(bool value) async {}
  @override
  Future<void> show() async => showCalls++;
  @override
  Future<bool> isVisible() async => visible;
  @override
  Future<void> restore() async => restoreCalls++;
  @override
  Future<void> setPreventClose(bool value) async {}
  @override
  Future<void> hideTitleBar() async {}
  @override
  Future<List<DisplayArea>> allDisplays() async => const [];
}
