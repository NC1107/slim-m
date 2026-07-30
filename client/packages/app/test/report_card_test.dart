// SPDX-License-Identifier: Apache-2.0
/// The report card names what a moderator is being asked to act on: a user
/// report's subject, and either kind's reporter, both resolved through
/// `GET /users` rather than left as the raw id the wire carries. See
/// `docs/research/audit-2026-07-30/screens.md`, "The report card identifies
/// nobody".
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/screens/admin/reports_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _tokens = TokenPair(
  userId: 'mod-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

String _reportJson({
  required String id,
  required String subjectKind,
  required String subjectId,
  String? reporterId,
  String? channelId,
  String? snapshot,
  String? subjectAuthorId,
  String reason = 'this is not okay',
}) => jsonEncode({
  'id': id,
  'reporter_id': reporterId,
  'subject_kind': subjectKind,
  'subject_id': subjectId,
  'channel_id': channelId,
  'reason': reason,
  'snapshot': snapshot,
  'subject_author_id': subjectAuthorId,
  'created_at': 0,
});

String _profileJson(String id, String displayName) => jsonEncode({
  'id': id,
  'username': displayName.toLowerCase(),
  'display_name': displayName,
  'created_at': 0,
});

/// Answers `GET /reports` with [reports] and `GET /users` from [profiles],
/// matching the wire contract both endpoints already document: a `/users`
/// id with nothing to report is simply absent from the response.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<String> reports,
  required Map<String, String> profiles,
}) async {
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            if (request.method == 'GET' && request.url.path == '/reports') {
              return http.Response(
                '[${reports.join(',')}]',
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.method == 'GET' && request.url.path == '/users') {
              final ids = request.url.queryParameters['ids']!.split(',');
              final found = [
                for (final id in ids)
                  if (profiles[id] case final name?) _profileJson(id, name),
              ];
              return http.Response(
                '[${found.join(',')}]',
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              '{}',
              404,
              headers: {'content-type': 'application/json'},
            );
          }),
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
        home: const ReportsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a message report names its reporter, not the raw id', (
    tester,
  ) async {
    await _pump(
      tester,
      reports: [
        _reportJson(
          id: 'report-1',
          subjectKind: 'message',
          subjectId: 'message-1',
          reporterId: 'reporter-1',
          channelId: 'channel-1',
          snapshot: 'go away',
        ),
      ],
      profiles: {'reporter-1': 'Alice'},
    );

    expect(find.textContaining('Alice'), findsOneWidget);
    expect(find.textContaining('reporter-1'), findsNothing);
  });

  testWidgets('a user report names its subject, not the raw id', (
    tester,
  ) async {
    await _pump(
      tester,
      reports: [
        _reportJson(
          id: 'report-2',
          subjectKind: 'user',
          subjectId: 'subject-1',
          reporterId: 'reporter-2',
        ),
      ],
      profiles: {'subject-1': 'Bob', 'reporter-2': 'Carol'},
    );

    expect(find.text('Bob'), findsOneWidget);
    expect(find.textContaining('Carol'), findsOneWidget);
    expect(find.textContaining('subject-1'), findsNothing);
    expect(find.textContaining('reporter-2'), findsNothing);
  });

  testWidgets(
    'a deleted account falls back honestly, for both subject and reporter',
    (tester) async {
      await _pump(
        tester,
        reports: [
          _reportJson(
            id: 'report-3',
            subjectKind: 'user',
            subjectId: 'subject-gone',
            // Null: the server already anonymized this account.
            reporterId: null,
          ),
        ],
        // subject-gone resolves to nothing, matching a 404 on that id.
        profiles: const {},
      );

      expect(find.text('Deleted account'), findsOneWidget);
      expect(find.textContaining('a deleted account'), findsOneWidget);
      expect(find.textContaining('subject-gone'), findsNothing);
    },
  );

  testWidgets('a long report body is bounded rather than left to grow', (
    tester,
  ) async {
    final longSnapshot = List.generate(80, (i) => 'line $i').join('\n');
    await _pump(
      tester,
      reports: [
        _reportJson(
          id: 'report-4',
          subjectKind: 'message',
          subjectId: 'message-2',
          reporterId: 'reporter-4',
          channelId: 'channel-1',
          snapshot: longSnapshot,
        ),
      ],
      profiles: {'reporter-4': 'Dana'},
    );

    final text = tester.widget<Text>(find.text(longSnapshot));
    expect(text.maxLines, 6);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  /// A message report names who wrote the message, which is the other half of
  /// "name the subject before asking for an irreversible close". It could not
  /// come from `subject_id`, which is the *message's* id; the server joins the
  /// author at read time and sends it as `subject_author_id`.
  testWidgets('a message report names the reported message\'s author', (
    tester,
  ) async {
    await _pump(
      tester,
      reports: [
        _reportJson(
          id: 'r1',
          subjectKind: 'message',
          subjectId: 'm1',
          reporterId: 'u-reporter',
          subjectAuthorId: 'u-author',
          snapshot: 'go away',
        ),
      ],
      profiles: {'u-reporter': 'Reporter Rae', 'u-author': 'Author Ash'},
    );

    expect(find.text('Author Ash'), findsOneWidget);
    expect(find.text('go away'), findsOneWidget);
  });

  /// A null author is not a lookup that failed. The server sends none when the
  /// message has been hard-deleted or the author anonymized, and saying so is
  /// more use to a moderator than a name that would be wrong.
  testWidgets('a message report whose author is gone says so', (tester) async {
    await _pump(
      tester,
      reports: [
        _reportJson(
          id: 'r1',
          subjectKind: 'message',
          subjectId: 'm1',
          reporterId: 'u-reporter',
          snapshot: 'go away',
        ),
      ],
      profiles: {'u-reporter': 'Reporter Rae'},
    );

    expect(find.text('Author no longer on this Space'), findsOneWidget);
  });
}
