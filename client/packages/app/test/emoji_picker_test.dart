// SPDX-License-Identifier: Apache-2.0
/// Tests for the emoji picker panel: the default category, search filtering
/// the whole catalog, category tabs switching which group shows, arrow-key
/// and Escape keyboard handling, and the recently-used shelf.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/providers/recent_emoji.dart';
import 'package:slimm_app/src/widgets/emoji_picker.dart';
import 'package:slimm_design_system/design_system.dart';

/// The catalog's own first entries, escaped rather than literal: the hygiene
/// gate forbids an emoji codepoint in client source, and these are user
/// content standing in for a reaction, not interface chrome.
const _grinningFace = '\u{1F600}'; // First catalog entry (smileys, default).
const _grinningFaceBigEyes = '\u{1F603}'; // Second catalog entry.
const _rofl = '\u{1F923}'; // Unique shortName "rofl"; a safe search probe.
const _grapes = '\u{1F347}'; // First "Food and drink" category entry.

Widget _harness(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'defaults to the smileys category, and picking a tile reports its '
    'emoji and records it as recently used',
    (tester) async {
      String? picked;
      late ProviderContainer container;

      await tester.pumpWidget(
        _harness(
          Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return EmojiPickerPanel(
                onSelect: (emoji) => picked = emoji,
                onClose: () {},
              );
            },
          ),
        ),
      );

      expect(find.text(_grinningFace), findsOneWidget);
      await tester.tap(find.text(_grinningFace));
      await tester.pump();

      expect(picked, _grinningFace);
      expect(container.read(recentEmojiProvider), contains(_grinningFace));
    },
  );

  testWidgets('a search query filters the whole catalog and hides the tabs', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(EmojiPickerPanel(onSelect: (_) {}, onClose: () {})),
    );

    expect(find.byTooltip('Food and drink'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'rofl');
    await tester.pump();

    expect(find.text(_rofl), findsOneWidget);
    expect(find.text(_grinningFace), findsNothing);
    expect(find.byTooltip('Food and drink'), findsNothing);
  });

  testWidgets('a category tab switches which group the grid shows', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(EmojiPickerPanel(onSelect: (_) {}, onClose: () {})),
    );

    expect(find.text(_grinningFace), findsOneWidget);

    await tester.tap(find.byTooltip('Food and drink'));
    await tester.pump();

    expect(find.text(_grapes), findsOneWidget);
    expect(find.text(_grinningFace), findsNothing);
  });

  testWidgets('arrow-down moves the highlight and Enter picks it', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      _harness(
        EmojiPickerPanel(onSelect: (emoji) => picked = emoji, onClose: () {}),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    // flutter_test's own docs: a raw Enter key never reaches `onSubmitted`,
    // since on a real device the engine, not Flutter, turns it into one.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(picked, _grinningFaceBigEyes);
  });

  testWidgets('Escape calls onClose', (tester) async {
    var closed = false;
    await tester.pumpWidget(
      _harness(
        EmojiPickerPanel(onSelect: (_) {}, onClose: () => closed = true),
      ),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(closed, isTrue);
  });

  testWidgets(
    'the recent tab only appears once there is a history, and shows it',
    (tester) async {
      await tester.pumpWidget(
        _harness(EmojiPickerPanel(onSelect: (_) {}, onClose: () {})),
      );
      expect(find.byTooltip('Recently used'), findsNothing);

      await tester.tap(find.text(_grinningFace));
      await tester.pump();

      expect(find.byTooltip('Recently used'), findsOneWidget);
    },
  );

  // The regression: this sheet ran to the physical bottom edge while its
  // sibling sheet did not, so the last emoji row sat under the home indicator.
  testWidgets('the sheet keeps its last row clear of the home indicator', (
    tester,
  ) async {
    const bottomInset = 34.0;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.padding = const FakeViewPadding(bottom: bottomInset);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showEmojiPickerSheet(context, onSelect: (_) {}),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byType(EmojiPickerPanel)).bottom,
      lessThanOrEqualTo(844.0 - bottomInset),
      reason: 'the panel must end above the home indicator, not under it',
    );
  });
}
