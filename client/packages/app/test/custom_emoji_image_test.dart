// SPDX-License-Identifier: Apache-2.0
/// Tests for drawing one of the deployment's own emoji, and for the lifetime
/// of the two providers behind it.
///
/// Both halves guard a decision that is invisible on screen when it is wrong.
/// A failed image fetch that renders nothing looks exactly like one still in
/// flight, and an `autoDispose` emoji provider looks exactly like a live one
/// until you count the fetches a scrolling transcript makes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/admin_providers.dart';
import 'package:slimm_app/src/providers/emoji_catalog_provider.dart';
import 'package:slimm_app/src/widgets/custom_emoji_image.dart';
import 'package:slimm_design_system/design_system.dart';

/// A 1x1 transparent PNG, so `Image.memory` decodes rather than throwing.
final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
    'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  ),
);

final _partyParrot = api.CustomEmoji(
  id: 'e-party_parrot',
  name: 'party_parrot',
  uploaderId: 'u1',
  createdAt: 1,
);

Widget _app(List<Override> overrides, Widget child) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: Scaffold(
      body: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

/// Watches the index the way a message row does, so unmounting this is
/// unmounting the last listener the index has.
class _IndexWatcher extends ConsumerWidget {
  const _IndexWatcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Text('${ref.watch(customEmojiIndexProvider).length}');
}

void main() {
  group('a fetch that failed', () {
    testWidgets('shows the missing-image glyph rather than blank space, which '
        'is indistinguishable from one still loading', (tester) async {
      await tester.pumpWidget(
        _app([
          customEmojiImageProvider.overrideWith(
            (ref, id) => Future<Uint8List>.error(StateError('gone')),
          ),
        ], const CustomEmojiImage(emojiId: 'e-party_parrot')),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(AppIcons.imageMissing), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('is told apart from one still in flight, which draws nothing '
        'and holds the space', (tester) async {
      final pending = Completer<Uint8List>();
      await tester.pumpWidget(
        _app([
          customEmojiImageProvider.overrideWith((ref, id) => pending.future),
        ], const CustomEmojiImage(emojiId: 'e-party_parrot')),
      );
      await tester.pump();

      expect(find.byIcon(AppIcons.imageMissing), findsNothing);
      expect(find.byType(Image), findsNothing);

      pending.complete(_png);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('decode cap', () {
    testWidgets('never decodes past the tile size it is drawn at', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app([
          customEmojiImageProvider.overrideWith((ref, id) async => _png),
        ], const CustomEmojiImage(emojiId: 'e-party_parrot', size: 24)),
      );
      await tester.pumpAndSettle();

      final image = tester.widget<Image>(find.byType(Image));
      final resized = image.image as ResizeImage;
      // 24dp at 2x, or a custom emoji upload decodes at its own full size.
      expect(resized.width, 48);
      expect(resized.height, 48);
    });
  });

  group('provider lifetime', () {
    testWidgets('the emoji index outlives the last widget watching it, so a '
        'transcript scrolling a row out does not refetch the set', (
      tester,
    ) async {
      var fetches = 0;
      final overrides = [
        customEmojiProvider.overrideWith((ref) async {
          fetches++;
          return [_partyParrot];
        }),
      ];

      await tester.pumpWidget(_app(overrides, const _IndexWatcher()));
      await tester.pumpAndSettle();
      expect(fetches, 1);

      await tester.pumpWidget(_app(overrides, const SizedBox.shrink()));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_app(overrides, const _IndexWatcher()));
      await tester.pumpAndSettle();

      expect(
        fetches,
        1,
        reason:
            'customEmojiIndexProvider must not be autoDispose: it is what '
            'holds the (autoDispose) list alive for the session',
      );
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('one emoji\'s bytes outlive the row that drew them, so the '
        'same emoji further down refetches nothing', (tester) async {
      var fetches = 0;
      final overrides = [
        customEmojiImageProvider.overrideWith((ref, id) async {
          fetches++;
          return _png;
        }),
      ];

      await tester.pumpWidget(
        _app(overrides, const CustomEmojiImage(emojiId: 'e-party_parrot')),
      );
      await tester.pumpAndSettle();
      expect(fetches, 1);

      await tester.pumpWidget(_app(overrides, const SizedBox.shrink()));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        _app(overrides, const CustomEmojiImage(emojiId: 'e-party_parrot')),
      );
      await tester.pumpAndSettle();

      expect(
        fetches,
        1,
        reason:
            'customEmojiImageProvider must not be autoDispose: the same '
            'emoji recurs down a transcript',
      );
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
