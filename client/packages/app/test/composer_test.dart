// SPDX-License-Identifier: Apache-2.0
/// Tests for the composer's send paths.
///
/// The defect these pin: the composer's only send trigger was a hardware
/// Enter key, which a soft keyboard cannot produce, so the app could not send
/// a message on a phone at all. Two paths now exist, and the desktop
/// shift+enter contract has to survive both.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/providers/typing_controller.dart';
import 'package:slimm_app/src/widgets/composer.dart';
import 'package:slimm_app/src/widgets/composer_extras.dart';
import 'package:slimm_app/src/widgets/emoji_picker.dart';
import 'package:slimm_app/src/widgets/emoji_picker_grid.dart';
import 'package:slimm_design_system/design_system.dart';

/// Stands in for the real controller, which would open a websocket
/// subscription the moment the first keystroke reaches it.
class _NoopTyping extends StateNotifier<Set<String>>
    implements TypingController {
  _NoopTyping() : super(const {});

  @override
  void notifyTyping() {}
}

class _Sends {
  int count = 0;
  List<String> ids = const [];

  Future<void> call(List<String> attachmentIds) async {
    count += 1;
    ids = attachmentIds;
  }
}

Widget _harness({
  required TextEditingController controller,
  required _Sends sends,
  required TargetPlatform platform,
}) {
  return ProviderScope(
    overrides: [
      typingControllerProvider.overrideWith((ref, channelId) => _NoopTyping()),
    ],
    child: MaterialApp(
      theme: buildTheme(
        Brightness.light,
        AppTokens.light,
      ).copyWith(platform: platform),
      home: Scaffold(
        body: Column(
          children: [
            const Spacer(),
            Composer(
              controller: controller,
              channelId: 'c1',
              channelName: 'general',
              onSend: sends.call,
            ),
          ],
        ),
      ),
    ),
  );
}

Finder get _sendButton => find.ancestor(
  of: find.byIcon(AppIcons.send),
  matching: find.byType(AppIconButton),
);

const _hintKey = Key('composer-newline-hint');

/// The glyph in the picker's first cell, read off the grid rather than
/// hardcoded: the catalog comes from the third-party `emojis` package, so a
/// package bump reorders it and a fixed literal would fail for a reason that
/// has nothing to do with the behaviour under test.
String _firstGridGlyph(WidgetTester tester) =>
    tester.widget<EmojiGrid>(find.byType(EmojiGrid)).emoji.first.char;

void main() {
  late TextEditingController controller;
  late _Sends sends;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    controller = TextEditingController();
    sends = _Sends();
  });

  tearDown(() => controller.dispose());

  testWidgets('a tap on the send button sends what was typed', (tester) async {
    await tester.pumpWidget(
      _harness(
        controller: controller,
        sends: sends,
        platform: TargetPlatform.iOS,
      ),
    );

    await tester.enterText(find.byType(TextField), 'hello there');
    await tester.pump();
    await tester.tap(_sendButton);
    await tester.pump();

    expect(sends.count, 1);
    expect(sends.ids, isEmpty);
  });

  testWidgets('the send button is disabled until there is something to send', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        controller: controller,
        sends: sends,
        platform: TargetPlatform.iOS,
      ),
    );

    expect(tester.widget<AppIconButton>(_sendButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    expect(tester.widget<AppIconButton>(_sendButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'hi');
    await tester.pump();
    expect(tester.widget<AppIconButton>(_sendButton).onPressed, isNotNull);
  });

  testWidgets(
    'on a touch platform the field asks the engine to send, not to insert '
    'a newline',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          controller: controller,
          sends: sends,
          platform: TargetPlatform.iOS,
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.pump();

      expect(
        tester.testTextInput.setClientArgs!['inputAction'],
        'TextInputAction.send',
      );
    },
  );

  testWidgets(
    "the soft keyboard's send action sends and leaves the keyboard up",
    (tester) async {
      await tester.pumpWidget(
        _harness(
          controller: controller,
          sends: sends,
          platform: TargetPlatform.iOS,
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'hello there');
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(sends.count, 1);
      expect(tester.testTextInput.isRegistered, isTrue);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );
    },
  );

  // An iPad is a soft-keyboard platform with a real Enter key, and one press
  // arrives twice: the engine performs the send action, the framework the key.
  testWidgets('a hardware return on a touch platform sends exactly once', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        controller: controller,
        sends: sends,
        platform: TargetPlatform.iOS,
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'hello there');
    await tester.pump();

    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      sends.count,
      1,
      reason:
          'the shortcut and the send action must not both be live on '
          'one platform',
    );
  });

  testWidgets(
    'on desktop the field keeps the newline action and its shortcut',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          controller: controller,
          sends: sends,
          platform: TargetPlatform.linux,
        ),
      );

      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'hello there');
      await tester.pump();

      expect(
        tester.testTextInput.setClientArgs!['inputAction'],
        'TextInputAction.newline',
      );

      // The framework half only: the newline INSERTION is the engine's work
      // (services/raw_keyboard.dart), so a widget test cannot observe it.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(sends.count, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(sends.count, 1);
    },
  );

  testWidgets(
    'the shift + enter hint is hidden on touch and shown on desktop',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          controller: controller,
          sends: sends,
          platform: TargetPlatform.iOS,
        ),
      );
      expect(find.byKey(_hintKey), findsOneWidget);
      expect(tester.widget<Visibility>(find.byKey(_hintKey)).visible, isFalse);
      final touchHeight = tester.getSize(find.byKey(_hintKey)).height;

      await tester.pumpWidget(
        _harness(
          controller: controller,
          sends: sends,
          platform: TargetPlatform.linux,
        ),
      );
      // MaterialApp lerps its theme, and ThemeData.lerp switches `platform` at
      // the halfway point, so the new value is not readable in the same frame.
      await tester.pump(kThemeAnimationDuration);
      expect(tester.widget<Visibility>(find.byKey(_hintKey)).visible, isTrue);
      expect(find.text('shift + enter for newline'), findsOneWidget);
      // It collapses on touch rather than reserving its height. The hint can
      // never be shown there, so holding a row open for it is wasted space on
      // the one layout with the least of it.
      expect(touchHeight, 0.0);
      expect(
        tester.getSize(find.byKey(_hintKey)).height,
        greaterThan(0.0),
        reason: 'desktop still shows it, so it still occupies its row',
      );
    },
  );

  testWidgets('the smile button opens the real picker, not a fixed glyph', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        controller: controller,
        sends: sends,
        platform: TargetPlatform.iOS,
      ),
    );

    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is AppIconButton && w.semanticLabel == 'Insert emoji',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(EmojiPickerPanel), findsOneWidget);
    expect(controller.text, isEmpty);
  });

  testWidgets('a picked emoji lands at the caret, not at the end', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        controller: controller,
        sends: sends,
        platform: TargetPlatform.iOS,
      ),
    );

    await tester.enterText(find.byType(TextField), 'hi there');
    controller.selection = const TextSelection.collapsed(offset: 2);
    await tester.pump();

    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is AppIconButton && w.semanticLabel == 'Insert emoji',
      ),
    );
    await tester.pumpAndSettle();

    final glyph = _firstGridGlyph(tester);
    await tester.tap(
      find.descendant(of: find.byType(EmojiGrid), matching: find.text(glyph)),
    );
    await tester.pumpAndSettle();

    expect(
      controller.text,
      'hi$glyph there',
      reason: 'nothing asserted the picked emoji reached the field at all',
    );
    expect(
      controller.selection.baseOffset,
      2 + glyph.length,
      reason:
          'the caret must follow what was inserted, or the next '
          'keystroke lands in front of it',
    );
  });

  group('touch density', () {
    testWidgets('a phone gets 44pt controls and keeps a usable field', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _harness(
          controller: controller,
          sends: sends,
          platform: TargetPlatform.iOS,
        ),
      );

      for (final element in find.byType(AppIconButton).evaluate()) {
        expect(
          tester.getSize(find.byWidget(element.widget)).shortestSide,
          greaterThanOrEqualTo(AppSizes.rowTouch),
        );
      }
      // Five 44pt controls would leave 90, measured. Nothing about the touch
      // pass is worth a composer you cannot read what you typed in.
      expect(
        tester.getSize(find.byType(ComposerField)).width,
        greaterThan(160.0),
      );
    });

    testWidgets('what leaves the row is still reachable from it', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _harness(
          controller: controller,
          sends: sends,
          platform: TargetPlatform.iOS,
        ),
      );

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is AppIconButton && w.semanticLabel == 'More actions',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Attach a file'), findsOneWidget);
      expect(find.text('Create a poll'), findsOneWidget);
      expect(find.text('Insert code'), findsOneWidget);
    });

    testWidgets('a desktop window keeps every control on the row at 30pt', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 900);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _harness(
          controller: controller,
          sends: sends,
          platform: TargetPlatform.linux,
        ),
      );

      expect(find.byType(AppIconButton), findsNWidgets(5));
      for (final element in find.byType(AppIconButton).evaluate()) {
        expect(
          tester.getSize(find.byWidget(element.widget)).shortestSide,
          AppSizes.rowPointer,
        );
      }
    });
  });
}
