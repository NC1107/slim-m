// SPDX-License-Identifier: Apache-2.0
/// An inline attachment image must never be asked to decode wider than it can
/// ever be drawn: a phone photo attached to a message is routinely megabytes
/// at full resolution, and the transcript never shows more than
/// [kInlineImageMax] logical pixels of it - half the message column, since an
/// uncapped preview filled a desktop screen and pushed the conversation off
/// it.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/attachment_bytes.dart';
import 'package:slimm_app/src/widgets/attachment_view.dart';
import 'package:slimm_design_system/design_system.dart';

const _attachment = api.Attachment(
  id: 'a1',
  filename: 'photo.png',
  contentType: 'image/png',
  size: 4,
);

Future<void> _pump(WidgetTester tester, Uint8List bytes) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        attachmentBytesProvider(
          _attachment.id,
        ).overrideWith((ref) async => bytes),
      ],
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const Scaffold(body: AttachmentView(attachment: _attachment)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the decode width is capped at the inline max, scaled by dpr', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await _pump(tester, Uint8List.fromList(const [1, 2, 3, 4]));

    // cacheWidth/cacheHeight land on the provider as a ResizeImage, not Image.
    final image = tester.widget<Image>(find.byType(Image));
    final resized = image.image as ResizeImage;
    expect(resized.width, (kInlineImageMax * 2).round());
    // Null, so the codec keeps the source's own aspect ratio.
    expect(resized.height, isNull);
  });

  testWidgets('at 1x the cap is the inline max in real pixels', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await _pump(tester, Uint8List.fromList(const [5, 6, 7, 8]));

    final image = tester.widget<Image>(find.byType(Image));
    final resized = image.image as ResizeImage;
    expect(resized.width, kInlineImageMax.round());
  });
}
