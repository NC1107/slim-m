// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Tests for the new-emoji card's two truth-telling gaps: a taken name must
/// not also promise the upload will succeed, and a picked image must be
/// visible, and reversible, rather than standing in for a checkmark.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/admin_providers.dart';
import 'package:slimm_app/src/screens/admin/emoji_upload_card.dart';
import 'package:slimm_design_system/design_system.dart';

/// A 1x1 transparent PNG, so `Image.memory` decodes rather than throwing.
final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
    'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  ),
);

final _existing = [
  const api.CustomEmoji(
    id: 'e-party_parrot',
    name: 'party_parrot',
    uploaderId: 'u1',
    createdAt: 1,
  ),
];

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<int>? picked,
}) async {
  final container = ProviderContainer(
    overrides: [
      customEmojiProvider.overrideWith((ref) async => _existing),
      if (picked != null)
        emojiImagePickerProvider.overrideWithValue(() async => picked),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const Scaffold(body: EmojiUploadCard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'a taken name hides the success preview instead of showing both',
    (tester) async {
      await _pump(tester);

      await tester.enterText(find.byType(TextField), 'party_parrot');
      await tester.pump();

      expect(find.text('Already taken.'), findsOneWidget);
      expect(
        find.textContaining('Will be added as'),
        findsNothing,
        reason:
            'the input already names the problem; a line promising the '
            'upload will succeed must not sit right beside it',
      );
    },
  );

  /// The card's own `_refusal` field already carried a submit failure inline;
  /// the picker-open failure used to bypass it with a `SnackBar` instead. See
  /// `check-error-surface.py` for the gate this shape is now caught by.
  testWidgets('a picker that throws is refused inline, not with a SnackBar', (
    tester,
  ) async {
    // Phone width: the inline callout takes space a SnackBar never claimed.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        customEmojiProvider.overrideWith((ref) async => _existing),
        emojiImagePickerProvider.overrideWithValue(
          () => throw StateError('no portal'),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: const Scaffold(body: EmojiUploadCard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose image'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(AppCallout), findsOneWidget);
    expect(
      find.textContaining('Could not open the file picker'),
      findsOneWidget,
    );
  });

  testWidgets('choosing an image shows it, and it can be unchosen', (
    tester,
  ) async {
    await _pump(tester, picked: _png);

    expect(find.byType(Image), findsNothing);
    expect(find.text('Choose image'), findsOneWidget);

    await tester.tap(find.text('Choose image'));
    await tester.pumpAndSettle();

    expect(
      find.byType(Image),
      findsNWidgets(2),
      reason: 'the two sizes an emoji is actually drawn at, inline and listed',
    );
    expect(find.text('Choose a different image'), findsOneWidget);

    await tester.tap(find.byIcon(AppIcons.dismiss));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.text('Choose image'), findsOneWidget);
  });
}
