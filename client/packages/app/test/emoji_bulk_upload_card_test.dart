// SPDX-License-Identifier: Apache-2.0
/// Widget tests for bulk emoji import (backlog #137): picking a zip drives
/// one `POST /emoji` per planned image, in order, and the final summary
/// reflects what the server actually did with each one.
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

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<int> zipBytes,
  required http.Response Function(http.Request) handleUpload,
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
            if (request.method == 'POST' && request.url.path == '/emoji') {
              return handleUpload(request);
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

http.Response _created(String name) => _json({
  'id': 'e-$name',
  'name': name,
  'uploader_id': 'admin',
  'created_at': 0,
}, status: 201);

void main() {
  testWidgets(
    'picking a zip uploads each image once, in order, named after its file '
    'stem, and skips the non-image entry without a request',
    (tester) async {
      final requests = <Uri>[];
      final zip = _buildZip({
        'party_blob.gif': [1, 2, 3],
        'Smile.png': [4, 5, 6],
        'readme.txt': [7, 8, 9],
      });

      await _pump(
        tester,
        zipBytes: zip,
        handleUpload: (request) {
          requests.add(request.url);
          return _created(request.url.queryParameters['name']!);
        },
      );

      await tester.tap(find.text('Choose a zip file'));
      await tester.pumpAndSettle();

      expect(
        requests,
        hasLength(2),
        reason: 'readme.txt is not an accepted image extension',
      );
      expect(requests[0].queryParameters['name'], 'party_blob');
      expect(requests[1].queryParameters['name'], 'smile');
      expect(find.textContaining('Added 2 of 2'), findsOneWidget);
      expect(find.text('Import another zip'), findsOneWidget);
    },
  );

  testWidgets(
    'a name colliding with an existing emoji is refused before any request, '
    'and the rest of the batch still runs',
    (tester) async {
      final requests = <Uri>[];
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
        handleUpload: (request) {
          requests.add(request.url);
          return _created(request.url.queryParameters['name']!);
        },
      );

      await tester.tap(find.text('Choose a zip file'));
      await tester.pumpAndSettle();

      expect(
        requests,
        hasLength(1),
        reason: 'taken.png never reaches the server',
      );
      expect(requests.single.queryParameters['name'], 'ok');
      expect(find.textContaining('Added 1 of 2'), findsOneWidget);
      expect(find.textContaining('taken.png'), findsOneWidget);
      expect(find.textContaining(':taken: is already used'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'a 409 the server returns for one file is shown against that file, '
    'without stopping the rest of the batch or using a SnackBar',
    (tester) async {
      final zip = _buildZip({
        'first.png': [1, 2, 3],
        'second.png': [4, 5, 6],
      });

      await _pump(
        tester,
        zipBytes: zip,
        handleUpload: (request) {
          final name = request.url.queryParameters['name']!;
          if (name == 'second') {
            return _json({
              'error': 'an emoji with that name already exists',
            }, status: 409);
          }
          return _created(name);
        },
      );

      await tester.tap(find.text('Choose a zip file'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Added 1 of 2'), findsOneWidget);
      expect(
        find.textContaining(
          'second.png: Could not add :second:. An emoji with that name '
          'already exists.',
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('an empty zip is refused inline rather than uploading nothing '
      'silently', (tester) async {
    await _pump(
      tester,
      zipBytes: _buildZip(const {}),
      handleUpload: (request) => _created('unused'),
    );

    await tester.tap(find.text('Choose a zip file'));
    await tester.pumpAndSettle();

    expect(find.textContaining('has no images in it'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
