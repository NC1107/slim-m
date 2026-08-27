// SPDX-License-Identifier: Apache-2.0
/// Dropping onto the emoji import card: a real `.zip` runs the exact same
/// import `emoji_bulk_upload_card_test.dart` already drives from the
/// button, and anything else is refused inline rather than silently
/// swallowed or shown as a SnackBar.
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/admin_providers.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/admin/emoji_bulk_upload_card.dart';
import 'package:slimm_design_system/design_system.dart';

const _tokens = api.TokenPair(
  userId: 'admin',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

List<int> _buildZip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(
      ArchiveFile(
        entry.key,
        entry.value.length,
        Uint8List.fromList(entry.value),
      ),
    );
  }
  return ZipEncoder().encodeBytes(archive);
}

http.Response _created(String name) => http.Response(
  jsonEncode({
    'id': 'e-$name',
    'name': name,
    'uploader_id': 'admin',
    'created_at': 0,
  }),
  201,
  headers: {'content-type': 'application/json'},
);

Future<void> _pump(
  WidgetTester tester, {
  required http.Response Function(http.Request) handleUpload,
}) async {
  final container = ProviderContainer(
    overrides: [
      customEmojiProvider.overrideWith((ref) async => const []),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: api.SessionStore(tokens: _tokens),
          httpClient: MockClient((request) async {
            if (request.method == 'POST' && request.url.path == '/emoji') {
              return handleUpload(request);
            }
            return http.Response('{}', 200);
          }),
        );
        ref.onDispose(client.close);
        return client;
      }),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const Scaffold(body: EmojiBulkUploadCard()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

DropTarget _dropTarget(WidgetTester tester) =>
    tester.widget<DropTarget>(find.byType(DropTarget));

void main() {
  testWidgets(
    'dropping a real zip runs the same import the picker button does',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      final requests = <Uri>[];
      final zip = _buildZip({
        'party_blob.gif': [1, 2, 3],
      });

      await _pump(
        tester,
        handleUpload: (request) {
          requests.add(request.url);
          return _created(request.url.queryParameters['name']!);
        },
      );

      final file = DropItemFile.fromData(
        Uint8List.fromList(zip),
        path: 'pack.zip',
      );
      _dropTarget(tester).onDragDone!(
        DropDoneDetails(
          files: [file],
          localPosition: Offset.zero,
          globalPosition: Offset.zero,
        ),
      );
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(requests.single.queryParameters['name'], 'party_blob');
      expect(find.textContaining('Added 1 of 1'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('dropping a non-zip file is refused with a reason', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await _pump(tester, handleUpload: (request) => _created('unused'));

    final file = DropItemFile.fromData(
      Uint8List.fromList([1, 2, 3]),
      path: 'holiday.png',
    );
    _dropTarget(tester).onDragDone!(
      DropDoneDetails(
        files: [file],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Drop a .zip file'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('dropping more than one file at once is refused with a reason', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await _pump(tester, handleUpload: (request) => _created('unused'));

    final a = DropItemFile.fromData(Uint8List.fromList([1]), path: 'a.zip');
    final b = DropItemFile.fromData(Uint8List.fromList([2]), path: 'b.zip');
    _dropTarget(tester).onDragDone!(
      DropDoneDetails(
        files: [a, b],
        localPosition: Offset.zero,
        globalPosition: Offset.zero,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('one zip file at a time'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
