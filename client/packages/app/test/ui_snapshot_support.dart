// SPDX-License-Identifier: Apache-2.0
/// The fixture the UI snapshot matrix renders: real fonts, a seeded session,
/// a seeded local store, and a container wired like the app's.
///
/// Kept out of the test file so the matrix there stays a list of sizes.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/sync_controller.dart';
import 'package:slimm_app/src/screens/home_shell.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_platform/platform.dart';

/// Where PNGs land. Gitignored: these are for looking at, not for diffing.
const snapshotDir = 'build/ui-snapshots';

/// Set SLIMM_UI_SNAPSHOTS=1 to write them. Unset, the matrix still runs and
/// still asserts no overflow, which is the part that belongs in CI.
bool get writingSnapshots => Platform.environment['SLIMM_UI_SNAPSHOTS'] == '1';

const fixtureTokens = api.TokenPair(
  userId: 'user-nick',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// The real faces, loaded by hand.
///
/// Without this the test binding draws every glyph as a filled box and every
/// icon as an empty square, which reads as a layout bug in the PNG rather
/// than as a missing font.
Future<void> loadRealFonts() async {
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }

  const design = '../design_system';
  await load('packages/slimm_design_system/IBM Plex Sans', [
    '$design/fonts/IBMPlexSans-Regular.ttf',
    '$design/fonts/IBMPlexSans-Medium.ttf',
    '$design/fonts/IBMPlexSans-SemiBold.ttf',
  ]);
  await load('packages/slimm_design_system/IBM Plex Mono', [
    '$design/fonts/IBMPlexMono-Regular.ttf',
    '$design/fonts/IBMPlexMono-Medium.ttf',
  ]);

  final lucide = File(
    '${_pubCache()}/lucide_icons_flutter-${_lucideVersion()}'
    '/assets/lucide.ttf',
  );
  if (lucide.existsSync()) {
    await load('packages/lucide_icons_flutter/Lucide', [lucide.path]);
  }
}

String _pubCache() {
  final home = Platform.environment['HOME'] ?? '';
  return Platform.environment['PUB_CACHE'] ?? '$home/.pub-cache/hosted/pub.dev';
}

/// Read from the lockfile rather than pinned here, so a bump does not
/// silently drop back to square icons.
String _lucideVersion() {
  final lock = File('../../pubspec.lock');
  if (!lock.existsSync()) return '';
  final lines = lock.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() != 'lucide_icons_flutter:') continue;
    for (var j = i; j < i + 8 && j < lines.length; j++) {
      final match = RegExp(r'version:\s*"?([^"\s]+)"?').firstMatch(lines[j]);
      if (match != null) return match.group(1)!;
    }
  }
  return '';
}

/// Real [SyncController] opens a socket to a server that is not there.
class _NoopSyncController extends SyncController {
  _NoopSyncController(super.ref);

  @override
  Future<void> start() async {}
}

/// Answers the reads the shell makes on its way up: the caller, the member
/// list, pins and a window of messages.
MockClient fixtureClient() => MockClient((request) async {
  final path = request.url.path;
  final Object body = switch (path) {
    '/me' => {
      'id': 'user-nick',
      'username': 'nick',
      'display_name': 'Nick',
      'created_at': 0,
      'permissions': -1,
    },
    _ when path.endsWith('/members') => [
      {
        'id': 'user-nick',
        'username': 'nick',
        'display_name': 'Nick',
        'created_at': 0,
        'roles': ['admin'],
      },
      {
        'id': 'user-ada',
        'username': 'ada',
        'display_name': 'Ada Lovelace',
        'created_at': 0,
        'roles': <String>[],
      },
    ],
    // A list is the right empty answer for the collection reads; the
    // read marker decodes a shape and type-errors on one.
    _ when path.endsWith('/read') => const {'last_read_seq': 3, 'unread': 0},
    _ when path.endsWith('/voice/roster') => const {'participants': <Object>[]},
    _ => const <Object>[],
  };
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
});

const fixtureChannels = [
  api.Channel(id: 'c-general', name: 'general', kind: 'text', createdAt: 0),
  api.Channel(
    id: 'c-design',
    name: 'design',
    kind: 'text',
    createdAt: 0,
    topic: 'tokens, type and the shell',
  ),
  api.Channel(id: 'c-main', name: 'main', kind: 'voice', createdAt: 0),
];

api.Message _message(
  int seq,
  String author,
  String content, {
  List<api.ReactionSummary> reactions = const [],
}) => api.Message(
  id: 'm-$seq',
  channelId: 'c-general',
  authorId: author,
  authorDisplayName: author == 'user-nick' ? 'Nick' : 'Ada Lovelace',
  seq: seq,
  content: content,
  createdAt: 1753600000000 + seq * 60000,
  editedAt: null,
  reactions: reactions,
);

final fixtureMessages = [
  _message(1, 'user-ada', 'The rail rows line up again at every width.'),
  _message(
    2,
    'user-nick',
    'Reactions render in colour now, not outlines.',
    reactions: const [
      api.ReactionSummary(emoji: '\u{1F389}', count: 2, reacted: true),
      api.ReactionSummary(emoji: '\u{2764}\u{FE0F}', count: 1, reacted: false),
    ],
  ),
  _message(
    3,
    'user-ada',
    'Long enough to wrap on a phone and prove the composer still clears '
        'the home indicator underneath it.',
  ),
];

/// A container wired like the app's, with the network and database swapped.
Future<({ProviderContainer container, SlimmDatabase db})>
fixtureContainer() async {
  final db = SlimmDatabase(NativeDatabase.memory());
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(
        api.SessionStore(tokens: fixtureTokens),
      ),
      syncControllerProvider.overrideWith(_NoopSyncController.new),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: fixtureClient(),
        );
        ref.onDispose(client.close);
        return client;
      }),
      databaseProvider.overrideWith((ref) => db),
    ],
  );
  final store = await container.read(storeProvider.future);
  await store.upsertChannels(fixtureChannels);
  await store.applyMessages(fixtureMessages);
  return (container: container, db: db);
}

/// The shell, on the real routes, at [location].
GoRouter fixtureRouter(String location) => GoRouter(
  initialLocation: location,
  routes: [
    ShellRoute(
      builder: (context, state, child) => HomeShell(child: child),
      routes: [
        GoRoute(
          path: '/channels',
          builder: (context, state) => const SizedBox.shrink(),
          routes: [
            GoRoute(
              path: ':channelId',
              builder: (context, state) => ConversationPane(
                channelId: state.pathParameters['channelId']!,
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Key on the boundary the PNG is taken from.
const snapshotBoundary = Key('ui_snapshot_boundary');

/// Rasterising is engine work the test's fake clock never completes, so it
/// has to run in the real zone or the test hangs holding a finished image.
Future<void> writeSnapshot(WidgetTester tester, String name) async {
  if (!writingSnapshots) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(snapshotBoundary),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    Directory(snapshotDir).createSync(recursive: true);
    File(
      '$snapshotDir/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Disposing before unmounting is what stops a pending debounce (the member
/// roster's, the read marker's) from outliving the test and hanging it.
Future<void> teardownFixture(
  WidgetTester tester,
  ProviderContainer container,
  SlimmDatabase db,
) async {
  container.dispose();
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  await db.close();
}
