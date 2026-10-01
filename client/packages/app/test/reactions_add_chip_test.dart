// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A message that already has a reaction ends its chips with a dashed "add"
/// chip, so another can be left without hovering for the toolbar or opening
/// the menu. Hidden while there are none.
///
/// Geometry throughout: the chip must sit on the chips' own line, at their
/// height, and open the picker where the width says it should.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/widgets/add_reaction_chip.dart';
import 'package:slimm_app/src/widgets/emoji_picker.dart';
import 'package:slimm_app/src/widgets/reactions_row.dart';
import 'package:slimm_design_system/design_system.dart';

import 'message_row_harness.dart';

const _two = [
  api.ReactionSummary(emoji: '\u{1F44D}', count: 3, reacted: true),
  api.ReactionSummary(emoji: '\u{1F602}', count: 1, reacted: false),
];

Widget _row({
  List<api.ReactionSummary> reactions = _two,
  ValueChanged<String>? onPick,
}) => harness(
  Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: const EdgeInsets.only(top: 100, left: 40),
      child: RepaintBoundary(
        key: const Key('boundary'),
        child: ReactionsRow(
          messageId: 'm1',
          reactions: reactions,
          onReactionTap: (_) {},
          onPickReaction: onPick ?? (_) {},
        ),
      ),
    ),
  ),
);

Finder get _add => find.byKey(ReactionsRow.addChipKey);

Future<void> _phone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets(
    'it trails the reaction chips on their own line at their height',
    (tester) async {
      await tester.pumpWidget(_row());
      await tester.pumpAndSettle();

      final chips = find.descendant(
        of: find.byType(Wrap),
        matching: find.byType(FocusableTapTarget),
      );
      final lastReaction = tester.getRect(chips.at(1));
      final add = tester.getRect(_add);
      expect(add.left, greaterThanOrEqualTo(lastReaction.right));
      expect(add.center.dy, closeTo(lastReaction.center.dy, 1));
      expect(add.height, lastReaction.height, reason: 'one hit height');
      final body = tester.getRect(find.byKey(AddReactionChip.bodyKey));
      expect(body.height, 24, reason: 'drawn at the reaction chip height');
      expect(body.width, lessThanOrEqualTo(40));
    },
  );

  testWidgets('it is absent while the message has no reactions', (
    tester,
  ) async {
    await tester.pumpWidget(_row(reactions: const []));
    await tester.pumpAndSettle();

    expect(_add, findsNothing);
    expect(tester.getSize(find.byType(ReactionsRow)), Size.zero);
  });

  testWidgets('it leaves with the last reaction instead of lingering', (
    tester,
  ) async {
    await tester.pumpWidget(_row());
    await tester.pumpAndSettle();
    expect(_add, findsOneWidget);

    await tester.pumpWidget(_row(reactions: const []));
    await tester.pump(const Duration(milliseconds: 20));

    expect(
      find.byType(FocusableTapTarget),
      findsNWidgets(2),
      reason: 'the two reaction chips are still playing their exit',
    );
    expect(_add, findsNothing);
  });

  testWidgets('its border is dashed, not a solid hairline', (tester) async {
    await tester.pumpWidget(_row());
    await tester.pumpAndSettle();

    final tokens = Theme.of(tester.element(_add)).extension<AppTokens>()!;
    final chip = tester.getRect(find.byKey(AddReactionChip.bodyKey));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('boundary')),
    );
    late ui.Image image;
    late ByteData bytes;
    await tester.runAsync(() async {
      image = await boundary.toImage();
      bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    });
    final origin = tester.getTopLeft(find.byKey(const Key('boundary')));
    final y = (chip.top - origin.dy + 0.5).floor();
    var transitions = 0;
    bool? previous;
    for (
      var x = (chip.left - origin.dx + 8).floor();
      x < (chip.right - origin.dx - 8).floor();
      x++
    ) {
      final i = (y * image.width + x) * 4;
      final pixel = Color.fromARGB(
        bytes.getUint8(i + 3),
        bytes.getUint8(i),
        bytes.getUint8(i + 1),
        bytes.getUint8(i + 2),
      );
      final ink = pixel != tokens.surfaceBase && pixel.a > 0;
      if (previous != null && ink != previous) transitions++;
      previous = ink;
    }
    expect(
      transitions,
      greaterThanOrEqualTo(2),
      reason: 'a solid edge has no gaps along its top',
    );
  });

  testWidgets('on a wide window it opens the picker under the chip', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(_row(onPick: (e) => picked = e));
    await tester.pumpAndSettle();

    await tester.tap(_add);
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byType(EmojiPickerPanel));
    final chip = tester.getRect(_add);
    expect(panel.top, closeTo(chip.bottom + 4, 8));
    expect(panel.left, closeTo(chip.left, 12));

    final glyph = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(EmojiPickerPanel),
            matching: find.byType(Text),
          ),
        )
        .firstWhere(
          (t) =>
              (t.data ?? '').runes.length == 1 &&
              t.data!.codeUnitAt(0) > 0x2000,
        );
    await tester.tap(find.text(glyph.data!).first);
    await tester.pumpAndSettle();
    expect(picked, glyph.data);
  });

  testWidgets('on a phone it opens the sheet, not a popup under a thumb', (
    tester,
  ) async {
    await _phone(tester);
    await tester.pumpWidget(_row());
    await tester.pumpAndSettle();

    await tester.tap(_add);
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byType(EmojiPickerPanel));
    expect(find.byType(EmojiPickerPanel), findsOneWidget);
    expect(
      panel.bottom,
      closeTo(800, 1),
      reason: 'docked to the window bottom',
    );
    expect(
      panel.width,
      closeTo(360 - 2 * AppSpacing.s8, 1),
      reason: 'the sheet spans the window less its gutters',
    );
  });

  testWidgets('on a phone the hit area reaches the touch minimum', (
    tester,
  ) async {
    await _phone(tester);
    await tester.pumpWidget(_row());
    await tester.pumpAndSettle();

    final hit = tester.getRect(_add);
    expect(hit.height, greaterThanOrEqualTo(AppSizes.rowTouch));
    expect(hit.width, greaterThanOrEqualTo(AppSizes.rowTouch));
  });
}
