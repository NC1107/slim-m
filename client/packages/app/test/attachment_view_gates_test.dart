// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The two media-performance gates on an inline attachment: with auto-download
/// off nothing is fetched until the tap, and with autoplay off a gif holds
/// under a play badge and only reveals on the tap. Both defaults leave the
/// attachment loading and animating on its own, which the plain
/// attachment_view_test already covers.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/attachment_bytes.dart';
import 'package:slimm_app/src/providers/media_preferences.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/attachment_view.dart';
import 'package:slimm_design_system/design_system.dart';

const _png = api.Attachment(
  id: 'p1',
  filename: 'photo.png',
  contentType: 'image/png',
  size: 4,
);

const _gif = api.Attachment(
  id: 'g1',
  filename: 'loop.gif',
  contentType: 'image/gif',
  size: 43,
);

/// A real 1x1 transparent gif, so the held-frame decode settles to a still
/// image rather than a shimmering placeholder pumpAndSettle would wait on.
final _gifBytes = base64Decode(
  'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
);

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

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer container,
  api.Attachment attachment,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: Scaffold(body: AttachmentView(attachment: attachment)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('auto-download off fetches nothing until the tap', (
    tester,
  ) async {
    var fetched = false;
    final container = _container([
      attachmentBytesProvider(_png.id).overrideWith((ref) async {
        fetched = true;
        return Uint8List.fromList(const [1, 2, 3, 4]);
      }),
    ]);
    await container
        .read(mediaAutoDownloadControllerProvider.notifier)
        .select(MediaAutoDownload.manual);

    await _pump(tester, container, _png);

    expect(find.text('Tap to load'), findsOneWidget);
    expect(fetched, isFalse, reason: 'held for download until asked');

    await tester.tap(find.text('Tap to load'));
    await tester.pumpAndSettle();

    expect(fetched, isTrue, reason: 'the tap is what triggers the fetch');
    expect(find.text('Tap to load'), findsNothing);
  });

  testWidgets('autoplay off holds a gif under a play badge until the tap', (
    tester,
  ) async {
    final container = _container([
      attachmentBytesProvider(_gif.id).overrideWith((ref) async => _gifBytes),
    ]);
    await container
        .read(gifAutoplayControllerProvider.notifier)
        .select(GifAutoplay.tapToPlay);

    await _pump(tester, container, _gif);

    // Downloaded (bytes resolved), but frozen under a play badge, not animating.
    expect(find.byIcon(AppIcons.play), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    await tester.tap(find.byIcon(AppIcons.play));
    await tester.pumpAndSettle();

    // Revealed: the badge is gone and the animating Image is in the tree.
    expect(find.byIcon(AppIcons.play), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });
}
