// SPDX-License-Identifier: Apache-2.0
/// The small-splash-then-handoff sequence added by decision 0012's
/// superseding section: [DesktopWindowShell.applyInitialGeometry] puts the
/// window into the fixed splash shape before the very first frame, and
/// [DesktopWindowShell.prepareHandoff]/[DesktopWindowShell.revealAfterHandoff]
/// swap it to the real saved geometry once bootstrap finishes - all driven
/// against a fake port, per decision 0012's own rule that this class of
/// logic stays automatable with no real display involved.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/desktop/desktop_window_shell.dart';
import 'package:slimm_app/src/desktop/window_geometry.dart';
import 'package:slimm_app/src/desktop/window_geometry_store.dart';

import 'support/fake_desktop_window_port.dart';

ProviderContainer _container() {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUp(() => DesktopWindowShell.debugReset());
  tearDown(DesktopWindowShell.debugReset);

  testWidgets('applyInitialGeometry sizes and centers the window at the '
      'fixed splash size, locks resizing, and hides the Linux title bar', (
    tester,
  ) async {
    final port = FakeDesktopWindowPort();
    DesktopWindowShell.debugPort = port;

    await DesktopWindowShell.applyInitialGeometry();

    expect(port.lastSize, DesktopWindowShell.splashWindowSize);
    expect(port.centerCalls, 1);
    expect(port.lastResizable, isFalse);
    expect(port.hideTitleBarCalls, 1);
    expect(DesktopWindowShell.frameless, isTrue);
  });

  testWidgets('prepareHandoff hides the window, unlocks resizing, and falls '
      'back to the default geometry with nothing saved yet', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final port = FakeDesktopWindowPort();
    DesktopWindowShell.debugPort = port;
    final container = _container();

    await DesktopWindowShell.prepareHandoff(container);

    expect(port.hideCalls, 1);
    expect(port.lastResizable, isTrue);
    expect(port.lastSize, WindowGeometry.fallback.windowedSize);
    expect(port.centerCalls, 1);
    expect(port.maximizeCalls, 0);
  });

  testWidgets('prepareHandoff restores a saved maximized run state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      windowGeometryPreferenceKey: jsonEncode(
        const WindowGeometry(
          windowedSize: WindowSize(width: 1400, height: 900),
          runState: WindowRunState.maximized,
        ).toJson(),
      ),
    });
    final port = FakeDesktopWindowPort();
    DesktopWindowShell.debugPort = port;
    final container = _container();

    await DesktopWindowShell.prepareHandoff(container);

    expect(port.hideCalls, 1);
    expect(port.lastSize, const WindowSize(width: 1400, height: 900));
    expect(port.maximizeCalls, 1);
  });

  testWidgets('revealAfterHandoff shows the window again once the real UI '
      'has had a frame to paint', (tester) async {
    final port = FakeDesktopWindowPort();
    DesktopWindowShell.debugPort = port;

    // endOfFrame only resolves once a frame runs, which needs an explicit pump here (a real host runs one on its own).
    final reveal = DesktopWindowShell.revealAfterHandoff();
    await tester.pump();
    await reveal;

    expect(port.showCalls, 1);
  });
}
