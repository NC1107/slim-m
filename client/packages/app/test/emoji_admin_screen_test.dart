// SPDX-License-Identifier: Apache-2.0
/// The custom emoji administration screen, driven through the real
/// [SlimmApi] against a mock transport, so the assertions are about the
/// requests that actually leave the client rather than about a stubbed
/// repository.
///
/// The picker is the one thing overridden: `file_picker` has no platform
/// implementation in a widget test, which is what
/// [emojiImagePickerProvider] exists for.
library;

import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/admin/emoji_screen.dart';
import 'package:slimm_app/src/screens/admin/emoji_upload_card.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// A one-pixel PNG, so the row's preview has real bytes to decode rather than
/// a shape only this test would ever produce.
const _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
];

Map<String, dynamic> _emojiJson(String id, String name) => {
  'id': id,
  'name': name,
  'uploader_id': 'self',
  'created_at': 1700000000000,
};

/// One request as the assertions read it: method, path, and the query the
/// upload carries its name in.
typedef Seen = ({String method, String path, String? name});

class _Server {
  _Server({
    this.emoji = const [],
    this.uploadStatus = 201,
    this.uploadBody,
    this.deleteThrows = false,
  });

  List<Map<String, dynamic>> emoji;
  int uploadStatus;
  String? uploadBody;

  /// Simulates a dropped connection rather than a server refusal, so the
  /// row's failure exercises the same transport path a real network blip
  /// would, not just a shaped 4xx body.
  bool deleteThrows;
  final seen = <Seen>[];

  http.Client client() => MockClient((request) async {
    final path = request.url.path;
    seen.add((
      method: request.method,
      path: path,
      name: request.url.queryParameters['name'],
    ));

    if (deleteThrows && request.method == 'DELETE') {
      throw const SocketException('connection refused');
    }
    if (path == '/emoji' && request.method == 'GET') {
      return http.Response(
        jsonEncode(emoji),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }
    if (path == '/emoji' && request.method == 'POST') {
      return http.Response(
        uploadBody ?? jsonEncode(_emojiJson('emoji-new', 'party_parrot')),
        uploadStatus,
        headers: const {'content-type': 'application/json'},
      );
    }
    if (path.endsWith('/image')) {
      return http.Response.bytes(
        _png,
        200,
        headers: const {'content-type': 'image/png'},
      );
    }
    if (request.method == 'DELETE') return http.Response('', 204);
    return http.Response('{}', 404);
  });
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  _Server server, {
  List<int>? picked,
}) async {
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
      emojiImagePickerProvider.overrideWithValue(() async => picked),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: server.client(),
        );
        ref.onDispose(api.close);
        return api;
      }),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: const EmojiScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('the list shows each emoji as the shortcode a member types', (
    tester,
  ) async {
    final server = _Server(
      emoji: [
        _emojiJson('emoji-1', 'party_parrot'),
        _emojiJson('emoji-2', 'ok'),
      ],
    );
    await _pump(tester, server);

    expect(find.text(':party_parrot:'), findsOneWidget);
    expect(find.text(':ok:'), findsOneWidget);
    // Each row shows the picture too, fetched through the same cache a
    // message row reads rather than a second copy of the same bytes.
    expect(find.byType(Image), findsNWidgets(2));
    expect(
      server.seen.where((r) => r.path.endsWith('/image')).map((r) => r.path),
      containsAll(<String>['/emoji/emoji-1/image', '/emoji/emoji-2/image']),
    );
  });

  testWidgets('typing a name shows what the server will store, before any '
      'request is made', (tester) async {
    final server = _Server();
    await _pump(tester, server);

    await tester.enterText(find.byType(AppInput), 'Party Parrot');
    await tester.pumpAndSettle();

    expect(find.text(':party_parrot:'), findsOneWidget);
    expect(
      server.seen.where((r) => r.method == 'POST'),
      isEmpty,
      reason: 'the preview must cost nothing; it is worked out locally',
    );
  });

  testWidgets('an unusable name explains itself and blocks the upload', (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server, picked: _png);

    await tester.enterText(find.byType(AppInput), '!!!');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose image'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Nothing usable there'),
      findsOneWidget,
      reason: 'the field normalises to nothing, so the button cannot work',
    );
    await tester.tap(find.text('Add emoji'));
    await tester.pumpAndSettle();
    expect(server.seen.where((r) => r.method == 'POST'), isEmpty);
  });

  testWidgets('the upload sends the normalised name, not what was typed', (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server, picked: _png);

    await tester.enterText(find.byType(AppInput), 'Party Parrot');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add emoji'));
    await tester.pumpAndSettle();

    final posts = server.seen.where((r) => r.method == 'POST').toList();
    expect(posts, hasLength(1));
    expect(posts.single.path, '/emoji');
    expect(posts.single.name, 'party_parrot');
  });

  /// The one refusal that is normal rather than exceptional, and the reason
  /// this screen does not settle for "request failed": the uploader has to
  /// learn the name is taken, not merely that something went wrong.
  testWidgets('a 409 is surfaced with the reason the server gave', (
    tester,
  ) async {
    final server = _Server(
      uploadStatus: 409,
      uploadBody: jsonEncode({
        'error': 'an emoji with that name already exists',
      }),
    );
    await _pump(tester, server, picked: _png);

    await tester.enterText(find.byType(AppInput), 'party_parrot');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add emoji'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('an emoji with that name already exists'),
      findsOneWidget,
    );
    expect(find.textContaining('request failed'), findsNothing);
  });

  /// A name already in the loaded list can only ever answer 409, so it is
  /// refused before the round trip rather than after it.
  testWidgets('a name the list already holds is refused without a request', (
    tester,
  ) async {
    final server = _Server(emoji: [_emojiJson('emoji-1', 'party_parrot')]);
    await _pump(tester, server, picked: _png);

    await tester.enterText(find.byType(AppInput), 'Party Parrot');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add emoji'));
    await tester.pumpAndSettle();

    expect(server.seen.where((r) => r.method == 'POST'), isEmpty);
    expect(find.text('Already taken.'), findsOneWidget);
  });

  testWidgets('removing one asks first, and only then deletes', (tester) async {
    final server = _Server(emoji: [_emojiJson('emoji-1', 'party_parrot')]);
    await _pump(tester, server);

    await tester.tap(find.byIcon(AppIcons.delete));
    await tester.pumpAndSettle();
    expect(find.text('Remove :party_parrot:?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(server.seen.where((r) => r.method == 'DELETE'), isEmpty);

    await tester.tap(find.byIcon(AppIcons.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    final deletes = server.seen.where((r) => r.method == 'DELETE').toList();
    expect(deletes, hasLength(1));
    expect(deletes.single.path, '/emoji/emoji-1');
  });

  /// A dropped connection while removing an emoji used to leave `_busy` true
  /// forever (cleared only inside the catch) and, before this pass, showed
  /// the raw `SocketException` string. This pins both: the row recovers, and
  /// what it says is a plain sentence.
  testWidgets(
    'a failed removal shows a safe sentence and the row stays usable',
    (tester) async {
      final server = _Server(
        emoji: [_emojiJson('emoji-1', 'party_parrot')],
        deleteThrows: true,
      );
      await _pump(tester, server);

      await tester.tap(find.byIcon(AppIcons.delete));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('SocketException'),
        findsNothing,
        reason: 'a Dart exception string helps nobody and reads as a crash',
      );
      expect(
        find.text(
          'Could not remove the :party_parrot: emoji: the server could '
          'not be reached. Nothing was changed.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<AppIconButton>(
              find.widgetWithIcon(AppIconButton, AppIcons.delete),
            )
            .onPressed,
        isNotNull,
        reason: 'the busy flag must clear on failure, not only on success',
      );
    },
  );
}
