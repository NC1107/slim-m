// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Widget tests for bulk emoji import (backlog #137): picking a zip drives
/// `POST /emoji/bulk` in chunks rather than one `POST /emoji` per image - see
/// `emoji_bulk_upload_card.dart`'s own module doc for why a per-image request
/// exhausted the upload rate limit on a large pack - and the final summary
/// reflects what the server actually did with each chunk.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
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

http.Response _json(Object value, {int status = 200}) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

/// The names a `POST /emoji/bulk` request asked for, in order.
List<String> _requestedNames(http.Request request) {
  final decoded = jsonDecode(request.body) as Map<String, dynamic>;
  final images = decoded['images'] as List<dynamic>;
  return images
      .map((e) => (e as Map<String, dynamic>)['name'] as String)
      .toList();
}

http.Response _bulkCreated(List<String> names) => _json([
  for (final name in names)
    {'id': 'e-$name', 'name': name, 'uploader_id': 'admin', 'created_at': 0},
], status: 201);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<int> zipBytes,
  required http.Response Function(http.Request) handleBulk,
  List<api.CustomEmoji> existing = const [],
}) async {
  final container = ProviderContainer(
    overrides: [
      customEmojiProvider.overrideWith((ref) async => existing),
      emojiZipPickerProvider.overrideWithValue(() async => zipBytes),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: api.SessionStore(tokens: _tokens),
          httpClient: MockClient((request) async {
            if (request.method == 'POST' && request.url.path == '/emoji/bulk') {
              return handleBulk(request);
            }
            return _json(const {});
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
  return container;
}

void main() {
  testWidgets(
    'picking a zip within the per-request cap uploads every image in one '
    'POST /emoji/bulk call, named after its file stem',
    (tester) async {
      final requests = <http.Request>[];
      final zip = _buildZip({
        'party_blob.gif': [1, 2, 3],
        'Smile.png': [4, 5, 6],
        'readme.txt': [7, 8, 9],
      });

      await _pump(
        tester,
        zipBytes: zip,
        handleBulk: (request) {
          requests.add(request);
          return _bulkCreated(_requestedNames(request));
        },
      );

      await tester.tap(find.text('Choose a zip file'));
      await tester.pumpAndSettle();

      expect(
        requests,
        hasLength(1),
        reason: 'both images fit in a single bulk request',
      );
      expect(_requestedNames(requests.single), [
        'party_blob',
        'smile',
      ], reason: 'readme.txt is not an accepted image extension');
      expect(find.textContaining('Added 2 of 2'), findsOneWidget);
      expect(find.text('Import another zip'), findsOneWidget);
    },
  );

  testWidgets(
    'a name colliding with an existing emoji is refused before any request, '
    'and the rest of the batch still uploads',
    (tester) async {
      final requests = <http.Request>[];
      final zip = _buildZip({
        'ok.png': [1, 2, 3],
        'taken.png': [4, 5, 6],
      });

      await _pump(
        tester,
        zipBytes: zip,
        existing: const [
          api.CustomEmoji(
            id: 'e-taken',
            name: 'taken',
            uploaderId: 'a',
            createdAt: 0,
          ),
        ],
        handleBulk: (request) {
          requests.add(request);
          return _bulkCreated(_requestedNames(request));
        },
      );

      await tester.tap(find.text('Choose a zip file'));
      await tester.pumpAndSettle();

      expect(requests, hasLength(1));
      expect(_requestedNames(requests.single), [
        'ok',
      ], reason: 'taken.png never reaches the server');
      expect(find.textContaining('Added 1 of 2'), findsOneWidget);
      expect(find.textContaining('taken.png'), findsOneWidget);
      expect(find.textContaining(':taken: is already used'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'a batch over the per-request cap splits into more than one bulk call, '
    'and only the failed chunk can be retried without re-uploading the '
    'chunk that already succeeded',
    (tester) async {
      final files = {
        for (var i = 0; i < 60; i++) 'e$i.png': [i, i, i],
      };
      final zip = _buildZip(files);

      var bulkCalls = 0;
      await _pump(
        tester,
        zipBytes: zip,
        handleBulk: (request) {
          bulkCalls++;
          final names = _requestedNames(request);
          // 60 images split 50/10; the 10-image chunk fails then retries ok.
          if (names.length == 10 && bulkCalls <= 2) {
            return _json({
              'error':
                  'too many requests just now. Wait a moment and '
                  'try again.',
            }, status: 429);
          }
          return _bulkCreated(names);
        },
      );

      await tester.tap(find.text('Choose a zip file'));
      await tester.pumpAndSettle();

      expect(
        bulkCalls,
        2,
        reason: '60 images split into a 50-image chunk and a 10-image chunk',
      );
      expect(find.textContaining('Added 50 of 60'), findsOneWidget);
      expect(
        find.textContaining('10 images could not be added:'),
        findsOneWidget,
        reason: 'ten failures sharing one cause collapse into one line',
      );
      // Not one line per failed file.
      expect(find.textContaining('e59.png:'), findsNothing);

      await tester.tap(find.text('Retry 10 failed'));
      await tester.pumpAndSettle();

      expect(bulkCalls, 3, reason: 'only the failed chunk is retried');
      expect(find.textContaining('Added 60 of 60'), findsOneWidget);
      expect(find.text('Retry 10 failed'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('an empty zip is refused inline rather than uploading nothing '
      'silently', (tester) async {
    await _pump(
      tester,
      zipBytes: _buildZip(const {}),
      handleBulk: (request) => _bulkCreated(_requestedNames(request)),
    );

    await tester.tap(find.text('Choose a zip file'));
    await tester.pumpAndSettle();

    expect(find.textContaining('has no images in it'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
