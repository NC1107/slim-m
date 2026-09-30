// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The picture-in-picture bridge: Android sends eligibility and hears the
/// window change; every other host never touches the channel.
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_platform/platform.dart';

const _channelName = 'top.npcserver.slimm/picture_in_picture';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final sent = <MethodCall>[];

  setUp(() {
    sent.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(_channelName),
      (call) async {
        sent.add(call);
        return null;
      },
    );
  });

  Future<void> native(bool inPip) =>
      binding.defaultBinaryMessenger.handlePlatformMessage(
        _channelName,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('modeChanged', inPip),
        ),
        (_) {},
      );

  test('android forwards eligibility', () async {
    final channel = PictureInPictureChannel(isAndroid: true);
    addTearDown(channel.dispose);

    await channel.setEligible(true);
    await channel.setEligible(false);

    expect(sent.map((c) => (c.method, c.arguments)), [
      ('setEligible', true),
      ('setEligible', false),
    ]);
  });

  test('entering and leaving the window reach the stream', () async {
    final channel = PictureInPictureChannel(isAndroid: true);
    addTearDown(channel.dispose);
    final seen = <bool>[];
    channel.modeChanges.listen(seen.add);

    await native(true);
    await native(false);
    await Future<void>.delayed(Duration.zero);

    expect(seen, [true, false]);
  });

  test('another host sends nothing and hears nothing', () async {
    final channel = PictureInPictureChannel(isAndroid: false);
    addTearDown(channel.dispose);
    final seen = <bool>[];
    channel.modeChanges.listen(seen.add);

    await channel.setEligible(true);
    await native(true);
    await Future<void>.delayed(Duration.zero);

    expect(sent, isEmpty);
    expect(seen, isEmpty);
  });

  test('a device with no native handler does not throw', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(_channelName),
      null,
    );
    final channel = PictureInPictureChannel(isAndroid: true);
    addTearDown(channel.dispose);

    await channel.setEligible(true);
  });
}
