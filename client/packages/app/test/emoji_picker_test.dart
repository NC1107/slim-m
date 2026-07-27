// SPDX-License-Identifier: Apache-2.0
/// Tests for the emoji picker panel: the default category, search filtering
/// the whole catalog, category tabs switching which group shows, arrow-key
/// and Escape keyboard handling, the recently-used shelf, and the
/// deployment's own custom emoji leading all of it.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart' show CustomEmoji;
import 'package:slimm_app/src/providers/emoji_catalog_provider.dart';
import 'package:slimm_app/src/providers/admin_providers.dart';
import 'package:slimm_app/src/providers/recent_emoji.dart';
import 'package:slimm_app/src/widgets/custom_emoji_image.dart';
import 'package:slimm_app/src/widgets/emoji_catalog.dart';
import 'package:slimm_app/src/widgets/emoji_picker.dart';
import 'package:slimm_app/src/widgets/emoji_picker_grid.dart';
import 'package:slimm_design_system/design_system.dart';

/// The catalog's own first entries, escaped rather than literal: the hygiene
/// gate forbids an emoji codepoint in client source, and these are user
/// content standing in for a reaction, not interface chrome.
const _grinningFace = '\u{1F600}'; // First catalog entry (smileys, default).
const _grinningFaceBigEyes = '\u{1F603}'; // Second catalog entry.
const _rofl = '\u{1F923}'; // Unique shortName "rofl"; a safe search probe.
const _grapes = '\u{1F347}'; // First "Food and drink" category entry.

/// A 1x1 transparent PNG: real bytes, so `Image.memory` decodes rather than
/// throwing, and small enough to sit in the test rather than a fixture file.
final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
    'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  ),
);

CustomEmoji _custom(String name) =>
    CustomEmoji(id: 'e-$name', name: name, uploaderId: 'u1', createdAt: 1);

/// [custom] null leaves the list provider alone, which is what every test
/// written before custom emoji existed sees: an unfetchable list, and so an
/// empty one.
Widget _harness(Widget child, {List<CustomEmoji>? custom}) => ProviderScope(
  overrides: [
    if (custom != null) customEmojiProvider.overrideWith((ref) => custom),
    customEmojiImageProvider.overrideWith((ref, id) => _png),
  ],
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

List<EmojiCategory> _tabs(WidgetTester tester) =>
    tester.widget<EmojiCategoryTabs>(find.byType(EmojiCategoryTabs)).categories;

List<PickerEmoji> _grid(WidgetTester tester) =>
    tester.widget<EmojiGrid>(find.byType(EmojiGrid)).emoji;

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

  testWidgets(
    "the deployment's own emoji lead the tabs, open first, and pick as a "
    'shortcode that the recent shelf then keeps',
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
          custom: [_custom('party_parrot'), _custom('shipit')],
        ),
      );

      expect(_tabs(tester).first, EmojiCategory.custom);
      expect(find.byTooltip('This server'), findsOneWidget);
      expect(find.byType(CustomEmojiImage), findsNWidgets(2));
      expect(find.text(_grinningFace), findsNothing);

      // The cell, not the image: a `RenderImage` has no children and does not
      // hit test itself, so the tap target is the detector wrapping it.
      await tester.tap(
        find
            .ancestor(
              of: find.byType(CustomEmojiImage),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      await tester.pump();

      expect(picked, ':party_parrot:');
      expect(container.read(recentEmojiProvider), contains(':party_parrot:'));

      await tester.tap(find.byTooltip('Recently used'));
      await tester.pump();

      expect(_grid(tester).single.token, ':party_parrot:');
    },
  );

  testWidgets(
    'a search matches a custom emoji by name, with or without the colons, '
    'and puts it above the unicode matches',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          EmojiPickerPanel(onSelect: (_) {}, onClose: () {}),
          custom: [_custom('party_parrot')],
        ),
      );

      // "parrot" is a unicode emoji too, so this also pins the ordering.
      await tester.enterText(find.byType(TextField), 'parrot');
      await tester.pump();

      expect(_grid(tester).first.token, ':party_parrot:');
      expect(_grid(tester).length, greaterThan(1));

      await tester.enterText(find.byType(TextField), ':party_parrot:');
      await tester.pump();

      expect(_grid(tester).single.token, ':party_parrot:');
    },
  );

  testWidgets('a deployment with no custom emoji shows no section for them', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        EmojiPickerPanel(onSelect: (_) {}, onClose: () {}),
        custom: const [],
      ),
    );

    expect(find.byTooltip('This server'), findsNothing);
    expect(find.byType(CustomEmojiImage), findsNothing);
    expect(_tabs(tester).first, EmojiCategory.smileysEmotion);
    expect(find.text(_grinningFace), findsOneWidget);
  });

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
