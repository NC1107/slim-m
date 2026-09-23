// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// `AppListRow`'s `mentioned` state, split out of `surfaces_test.dart` to
/// keep that file under the review budget.
///
/// The shape tests below exist because colour alone used to be the only cue
/// between a mention and a plain unread row: same 6x6 circle, [accentFill]
/// versus [textPrimary]. That is invisible to a viewer who cannot separate
/// the two hues, so a mention now paints as a diamond instead. The greyscale
/// silhouette test is the one that actually pins this - see
/// `presence_desaturation_test.dart` for the same technique applied to
/// [AppStatusDot], and its own note on why a binarised ink mask, not a raw
/// pixel diff, is the only comparison that does not just re-measure colour.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

Future<void> _pump(WidgetTester tester, Widget child, {AppTokens? tokens}) {
  final t = tokens ?? AppTokens.light;
  return tester.pumpWidget(
    MaterialApp(
        theme: buildTheme(Brightness.light, t),
        home: Scaffold(body: Center(child: child))),
  );
}

/// The nearest [TweenAnimationBuilder] ancestor of a dot key: the pop-in
/// wrapper that actually occupies the row's trailing slot, as opposed to the
/// dot's own inner render object, which is smaller once it is a diamond.
Size _dotSlotSize(WidgetTester tester, Key dotKey) {
  final slot = find.ancestor(
    of: find.byKey(dotKey),
    matching: find.byType(TweenAnimationBuilder<double>),
  );
  return tester.getSize(slot.first);
}

/// Rec. 709 luma, matching `presence_desaturation_test.dart`'s conversion.
double _luma(double r, double g, double b) =>
    0.2126 * r + 0.7152 * g + 0.0722 * b;

/// How far a pixel's grey must sit from the surface's own grey to count as
/// ink, not background.
const double _inkThreshold = 0.15;

List<bool> _inkMask(ByteData rgba, Color surface) {
  final background = _luma(surface.r, surface.g, surface.b);
  final mask = <bool>[];
  for (var i = 0; i < rgba.lengthInBytes; i += 4) {
    final grey = _luma(
      rgba.getUint8(i) / 255,
      rgba.getUint8(i + 1) / 255,
      rgba.getUint8(i + 2) / 255,
    );
    mask.add((grey - background).abs() > _inkThreshold);
  }
  return mask;
}

int _differing(List<bool> a, List<bool> b) {
  var count = 0;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) count++;
  }
  return count;
}

/// A whole row's ink mask. The label, padding and font are identical between
/// the two states this is used to compare, so every differing pixel comes
/// from the dot itself, not from anything else in the row.
Future<List<bool>> _rowInkMask(
  WidgetTester tester, {
  required bool unread,
  required bool mentioned,
}) async {
  const tokens = AppTokens.light;
  final key = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light, tokens),
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: tokens.surfaceBase,
            child: SizedBox(
              width: 240,
              child: AppListRow(
                  label: 'general', unread: unread, mentioned: mentioned),
            ),
          ),
        ),
      ),
    ),
  );
  // Let the dot's pop-in (opacity and scale) finish before capturing it.
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();

  late List<bool> mask;
  // Rasterising is engine work the fake clock never finishes; leave its zone.
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 4);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    mask = _inkMask(bytes!, tokens.surfaceBase);
  });
  return mask;
}

void main() {
  group('AppListRow mentioned', () {
    testWidgets(
        'mentioned paints the dot in accentFill and reads as a distinct key from a plain unread dot',
        (tester) async {
      const tokens = AppTokens.light;

      await _pump(
        tester,
        const SizedBox(
            width: 240, child: AppListRow(label: 'general', mentioned: true)),
      );
      expect(
        find.byKey(AppListRow.mentionDotKey),
        findsOneWidget,
        reason: 'a mention must be findable by its own key, not by colour',
      );
      expect(
        find.byKey(AppListRow.unreadDotKey),
        findsNothing,
        reason: 'the plain unread dot and the mention dot are never both shown',
      );
      final dot = tester.widget<DecoratedBox>(
        find.byKey(AppListRow.mentionDotKey),
      );
      expect(
        (dot.decoration as BoxDecoration).color,
        tokens.accentFill,
        reason: 'a mention is one of the seven closed accent roles',
      );
    });

    testWidgets('mentioned is emphasised the same way selected or unread is',
        (tester) async {
      await _pump(tester,
          const SizedBox(width: 240, child: AppListRow(label: 'general')));
      final plainStyle = tester.widget<Text>(find.text('general')).style!;

      await _pump(
        tester,
        const SizedBox(
            width: 240, child: AppListRow(label: 'general', mentioned: true)),
      );
      final mentionedStyle = tester.widget<Text>(find.text('general')).style!;
      expect(mentionedStyle.fontWeight, AppWeights.medium);
      expect(mentionedStyle.fontWeight, isNot(plainStyle.fontWeight));
    });

    testWidgets(
        'mentioned is a diamond, not a recoloured circle, so shape carries '
        'the distinction and colour only reinforces it', (tester) async {
      await _pump(
        tester,
        const SizedBox(
            width: 240, child: AppListRow(label: 'general', unread: true)),
      );
      final unreadShape = tester
          .widget<DecoratedBox>(find.byKey(AppListRow.unreadDotKey))
          .decoration as BoxDecoration;
      expect(
        unreadShape.borderRadius,
        BorderRadius.circular(AppRadii.full),
        reason: 'unread keeps its circle',
      );

      await _pump(
        tester,
        const SizedBox(
            width: 240, child: AppListRow(label: 'general', mentioned: true)),
      );
      final mentionShape = tester
          .widget<DecoratedBox>(find.byKey(AppListRow.mentionDotKey))
          .decoration as BoxDecoration;
      expect(
        mentionShape.borderRadius,
        isNot(BorderRadius.circular(AppRadii.full)),
        reason: 'a mention must not paint the same rounded silhouette unread '
            'does; that would leave colour as the only cue again',
      );
      // The pop-in animation adds its own Transform.scale, so only assert one ancestor rotates.
      final ancestorTransforms = tester.widgetList<Transform>(
        find.ancestor(
          of: find.byKey(AppListRow.mentionDotKey),
          matching: find.byType(Transform),
        ),
      );
      expect(
        ancestorTransforms.any((t) => t.transform.storage[1].abs() > 1e-6),
        isTrue,
        reason: 'the mention dot is rotated into a diamond, not just '
            'repainted in a different colour',
      );
    });

    testWidgets('the dot slot is the same size whichever shape it holds',
        (tester) async {
      await _pump(
        tester,
        const SizedBox(
            width: 240, child: AppListRow(label: 'general', unread: true)),
      );
      final unreadSlot = _dotSlotSize(tester, AppListRow.unreadDotKey);

      await _pump(
        tester,
        const SizedBox(
            width: 240, child: AppListRow(label: 'general', mentioned: true)),
      );
      final mentionSlot = _dotSlotSize(tester, AppListRow.mentionDotKey);

      expect(
        mentionSlot,
        unreadSlot,
        reason: 'swapping shapes must not reflow the row around the dot, the '
            'same property the kebab slot already guarantees',
      );
    });

    testWidgets(
        'a mention that is also unread renders only the diamond, never a '
        'second dot alongside it', (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 240,
          child: AppListRow(label: 'general', unread: true, mentioned: true),
        ),
      );
      expect(find.byKey(AppListRow.mentionDotKey), findsOneWidget);
      expect(
        find.byKey(AppListRow.unreadDotKey),
        findsNothing,
        reason: 'a mention already implies unread; a plain dot next to the '
            'diamond would just be noise for a state the diamond alone names',
      );
    });

    testWidgets(
        'unread and mentioned still read as different silhouettes once '
        'colour is removed', (tester) async {
      final unreadMask =
          await _rowInkMask(tester, unread: true, mentioned: false);
      final mentionMask =
          await _rowInkMask(tester, unread: false, mentioned: true);

      expect(unreadMask, hasLength(mentionMask.length));
      final difference = _differing(unreadMask, mentionMask);
      expect(
        difference,
        greaterThan(30),
        reason: 'once colour is gone, a circle and a diamond drawn in the '
            'same 6x6 box still disagree on a quarter of it; an equal '
            'silhouette here would mean only colour ever told them apart',
      );
    });
  });
}
