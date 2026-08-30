// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Dropping onto the emoji import card: a real `.zip` drives the exact same
/// chunked `POST /emoji/bulk` path `emoji_bulk_upload_card_test.dart` already
/// exercises from the button - never a second, unchunked import route - and
/// anything else is refused inline rather than silently swallowed or shown
/// as a SnackBar.
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

/// The names a `POST /emoji/bulk` request asked for, in order - mirrors
/// `emoji_bulk_upload_card_test.dart`'s own helper of the same name.
List<String> _requestedNames(http.Request request) {
  final decoded = jsonDecode(request.body) as Map<String, dynamic>;
  final images = decoded['images'] as List<dynamic>;
  return images
      .map((e) => (e as Map<String, dynamic>)['name'] as String)
      .toList();
}

http.Response _bulkCreated(List<String> names) => http.Response(
  jsonEncode([
    for (final name in names)
      {'id': 'e-$name', 'name': name, 'uploader_id': 'admin', 'created_at': 0},
  ]),
  201,
  headers: {'content-type': 'application/json'},
);

Future<void> _pump(
  WidgetTester tester, {
  required http.Response Function(http.Request) handleBulk,
}) async {
  final container = ProviderContainer(
    overrides: [
      customEmojiProvider.overrideWith((ref) async => const []),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: api.SessionStore(tokens: _tokens),
          httpClient: MockClient((request) async {
            if (request.method == 'POST' && request.url.path == '/emoji/bulk') {
              return handleBulk(request);
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
      final requestedBatches = <List<String>>[];
      final zip = _buildZip({
        'party_blob.gif': [1, 2, 3],
      });

      await _pump(
        tester,
        handleBulk: (request) {
          final names = _requestedNames(request);
          requestedBatches.add(names);
          return _bulkCreated(names);
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

      expect(
        requestedBatches,
        [
          ['party_blob'],
        ],
        reason:
            'one chunked POST /emoji/bulk request, the same path the '
            'button drives',
      );
      expect(find.textContaining('Added 1 of 1'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('dropping a non-zip file is refused with a reason', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await _pump(tester, handleBulk: (request) => _bulkCreated(const []));

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
    await _pump(tester, handleBulk: (request) => _bulkCreated(const []));

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
