// SPDX-License-Identifier: Apache-2.0
/// Regression for the tray reaching every real launch with an icon but no
/// menu: `tray_manager`'s Linux plugin has no handler for `setToolTip`
/// (`tray_manager_plugin.cc` only implements `setTitle`), so the call threw
/// `MissingPluginException` and used to abort `DesktopTrayController.start()`
/// before it ever reached `setContextMenu` - confirmed live on the owner's
/// KDE session via `busctl`'s `GetLayout` on the exported dbusmenu object
/// showing zero children. This drives the real `start()` against a mocked
/// `tray_manager` channel that fails `setToolTip` the same way, and asserts
/// the context menu is still built.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/tray/desktop_tray_controller.dart';

import '../voice_controller_harness.dart';
import 'support/fake_desktop_window_port.dart';

const _channel = MethodChannel('tray_manager');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('a backend with no setToolTip handler still gets a populated context '
      'menu', () async {
    final harness = VoiceHarness();
    harness.controllerWith(FakeSession(), voiceApi());
    addTearDown(harness.dispose);

    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          if (call.method == 'setToolTip') {
            throw MissingPluginException('setToolTip: linux has none');
          }
          return true;
        });

    final controller = DesktopTrayController(
      port: FakeDesktopWindowPort(),
      container: harness.container,
    );

    await controller.start();
    controller.dispose();

    expect(calls.map((call) => call.method), contains('setContextMenu'));
    final menuCall = calls.firstWhere(
      (call) => call.method == 'setContextMenu',
    );
    final menu = (menuCall.arguments as Map)['menu'] as Map;
    final items = menu['items'] as List;
    expect(items, isNotEmpty);
    expect(items.first['label'], 'Show/Hide slim-m');
  });
}
