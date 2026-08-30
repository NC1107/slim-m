// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The two halves of a notification tap, and why one is not enough.
///
/// A tap is the ordinary way a killed app gets launched, so the native side
/// has to hold it until Dart exists to ask; a tap while the app is already
/// running has nothing to hold and arrives as a call instead. Neither path
/// covers the other, so both are driven here.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_platform/platform.dart';

const _channelName = 'top.npcserver.slimm/push_tap';

/// Stands in for `AppDelegate.swift`: answers `takeInitialTap` once and then
/// with null, exactly as the native side clears what it hands over.
class _FakeNative {
  _FakeNative(this.binding, {String? initial}) : _initial = initial {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(_channelName),
      (call) async {
        calls.add(call.method);
        if (call.method != 'takeInitialTap') return null;
        final taken = _initial;
        _initial = null;
        return taken;
      },
    );
  }

  final TestDefaultBinaryMessengerBinding binding;
  final calls = <String>[];
  String? _initial;

  /// Drives the native-to-Dart direction the way a live tap does.
  Future<void> tap(String channelId) {
    return binding.defaultBinaryMessenger.handlePlatformMessage(
      _channelName,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('onNotificationTap', channelId),
      ),
      (_) {},
    );
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('a tap while running reaches the stream', () async {
    final native = _FakeNative(binding);
    final channel = NotificationTapChannel(isIOS: true);
    addTearDown(channel.dispose);

    final seen = <String>[];
    channel.taps.listen(seen.add);
    await native.tap('channel-1');
    await Future<void>.delayed(Duration.zero);

    expect(seen, ['channel-1']);
  });

  test('a launch tap is answered once and then forgotten', () async {
    final native = _FakeNative(binding, initial: 'channel-1');
    final channel = NotificationTapChannel(isIOS: true);
    addTearDown(channel.dispose);

    expect(await channel.takeInitial(), 'channel-1');
    expect(
      await channel.takeInitial(),
      isNull,
      reason: 'a tap answered on every launch would keep dragging someone '
          'back to a channel they had since navigated away from',
    );
    expect(native.calls, ['takeInitialTap', 'takeInitialTap']);
  });

  test('an empty channel id is not a destination', () async {
    _FakeNative(binding, initial: '');
    final channel = NotificationTapChannel(isIOS: true);
    addTearDown(channel.dispose);

    expect(await channel.takeInitial(), isNull);
  });

  test('off iOS nothing is asked and nothing arrives', () async {
    final native = _FakeNative(binding, initial: 'channel-1');
    final channel = NotificationTapChannel(isIOS: false);
    addTearDown(channel.dispose);

    expect(await channel.takeInitial(), isNull);
    expect(
      native.calls,
      isEmpty,
      reason: 'Android cannot open the sealed envelope, so there is no '
          'channel id for it to answer with',
    );
  });

  test('a missing native handler is not a launch failure', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(_channelName),
      null,
    );
    final channel = NotificationTapChannel(isIOS: true);
    addTearDown(channel.dispose);

    expect(await channel.takeInitial(), isNull);
  });
}
