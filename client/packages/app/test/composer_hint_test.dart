// SPDX-License-Identifier: Apache-2.0
/// The composer's placeholder text, for the one channel kind whose name is
/// genuinely empty: a thread (see ChannelScreen's `channelName`, `channel?.name
/// ?? ''`), which reused the ordinary "Message #$channelName" hint and
/// rendered a dangling "Message #" with nothing after the hash.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'composer_harness.dart';

const _hintKey = Key('composer-hint');

void main() {
  late TextEditingController controller;
  late Sends sends;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    controller = TextEditingController();
    sends = Sends();
  });

  tearDown(() => controller.dispose());

  testWidgets('a named channel still shows "Message #name"', (tester) async {
    await tester.pumpWidget(
      composerHarness(
        controller: controller,
        sends: sends,
        platform: TargetPlatform.iOS,
        channelName: 'general',
      ),
    );

    final hint = tester.widget<Text>(find.byKey(_hintKey));
    expect(hint.textSpan!.toPlainText(), 'Message #general');
  });

  testWidgets('an empty channel name (a thread) drops the hash entirely', (
    tester,
  ) async {
    await tester.pumpWidget(
      composerHarness(
        controller: controller,
        sends: sends,
        platform: TargetPlatform.iOS,
        channelName: '',
      ),
    );

    final hint = tester.widget<Text>(find.byKey(_hintKey));
    expect(hint.textSpan!.toPlainText(), 'Message');
  });
}
