// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The link preview card: renders a fetched preview's text and image, and
/// renders nothing at all for a missing one - never an error surface - the
/// same rule attachments follow when a fetch or decode fails.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/link_preview.dart';
import 'package:slimm_app/src/providers/media_preferences.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/link_preview_card.dart';
import 'package:slimm_design_system/design_system.dart';

const _url = 'https://example.com/article';

ProviderContainer _container(List<Override> overrides) {
  SharedPreferences.setMockInitialValues({});
  final container = ProviderContainer(
    overrides: [
      preferencesProvider.overrideWith(
        (ref) => SharedPreferences.getInstance(),
      ),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Future<void> _pump(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const Scaffold(body: LinkPreviewCard(url: _url)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a resolved preview shows its site name, title and description', (
    tester,
  ) async {
    final container = _container([
      linkPreviewProvider(_url).overrideWith(
        (ref) async => const LinkPreview(
          url: _url,
          title: 'An interesting article',
          description: 'What it is about.',
          siteName: 'Example News',
        ),
      ),
    ]);
    await _pump(tester, container);

    expect(find.text('Example News'), findsOneWidget);
    expect(find.text('An interesting article'), findsOneWidget);
    expect(find.text('What it is about.'), findsOneWidget);
  });

  testWidgets('a null preview (disabled or no unfurl) renders nothing', (
    tester,
  ) async {
    final container = _container([
      linkPreviewProvider(_url).overrideWith((ref) async => null),
    ]);
    await _pump(tester, container);

    expect(tester.takeException(), isNull);
    expect(find.text('Example News'), findsNothing);
    expect(find.byType(LinkPreviewCard), findsOneWidget);
  });

  testWidgets(
    'a preview with an image respects auto-download off until tapped',
    (tester) async {
      final bytes = Uint8List.fromList(const [1, 2, 3, 4]);
      final container = _container([
        linkPreviewProvider(_url).overrideWith(
          (ref) async => const LinkPreview(
            url: _url,
            title: 'An article',
            imageToken: 'tok1',
          ),
        ),
        linkPreviewImageBytesProvider(
          'tok1',
        ).overrideWith((ref) async => bytes),
      ]);
      await container
          .read(mediaAutoDownloadControllerProvider.notifier)
          .select(MediaAutoDownload.manual);

      await _pump(tester, container);

      expect(find.text('Tap to load preview'), findsOneWidget);
      expect(find.byType(Image), findsNothing);

      await tester.tap(find.text('Tap to load preview'));
      await tester.pumpAndSettle();

      expect(find.text('Tap to load preview'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    },
  );
}
