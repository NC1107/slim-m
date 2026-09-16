// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The administrator's half of account recovery:
/// `widgets/reset_code_sheet.dart` issuing a one-time code against
/// `POST /admin/users/{userId}/reset-code`.
///
/// The load-bearing behaviour is that opening the sheet does not issue
/// anything. A code is one-time and unreadable afterwards, so a sheet that
/// fetched on open would burn one every time a menu was opened by accident.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/widgets/reset_code_sheet.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';

const _code = 'RESET-CODE-VISIBLE-ONCE';

/// Issuing needs ADMINISTRATOR, so the call is authenticated; without a
/// session the request never leaves the client.
const _tokens = TokenPair(
  userId: 'admin-1',
  accessToken: 'access-1',
  refreshToken: 'refresh-1',
  accessExpiresAt: 0,
);

/// Counts issue calls so a test can prove one was, or was not, made.
http.Client _issuing({int status = 200}) {
  return MockClient((request) async {
    if (request.url.path.endsWith('/reset-code')) {
      _issued.add(request.url.path);
      if (status != 200) {
        return http.Response(
          jsonEncode({'error': 'forbidden'}),
          status,
          headers: const {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'code': _code,
          'expires_at': DateTime.utc(2031, 5, 4, 12).millisecondsSinceEpoch,
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 200);
  });
}

late List<String> _issued;

Future<void> _open(WidgetTester tester, {int status = 200}) async {
  _issued = <String>[];
  final client = _issuing(status: status);
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      serverUrlProvider.overrideWith(
        (ref) => Uri.parse('https://chat.example'),
      ),
      sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: ref.watch(serverUrlProvider),
          session: ref.watch(sessionProvider),
          httpClient: client,
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
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showResetCodeSheet(
                  context,
                  subjectId: 'user-9',
                  subjectName: 'Ada',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opening the sheet issues nothing until asked', (tester) async {
    await _open(tester);

    expect(
      _issued,
      isEmpty,
      reason:
          'a code cannot be read twice, so opening this by accident must not '
          'burn one',
    );
    expect(find.text('Generate code'), findsOneWidget);
    expect(find.text(_code), findsNothing);
  });

  testWidgets('generating shows the code and names who it is for', (
    tester,
  ) async {
    await _open(tester);

    await tester.tap(find.text('Generate code'));
    await tester.pumpAndSettle();

    expect(_issued, hasLength(1));
    expect(_issued.single, contains('user-9'));
    expect(find.text(_code), findsOneWidget);
    expect(find.textContaining('Ada'), findsWidgets);
    expect(
      find.textContaining('signs them out everywhere'),
      findsOneWidget,
      reason:
          'spending a code revokes every session; an admin handing one over '
          'should know that before they do',
    );
    expect(
      find.text('Generate code'),
      findsNothing,
      reason: 'a second press would silently invalidate the code just shown',
    );
  });

  testWidgets('a refused issue reports inline and leaves the sheet usable', (
    tester,
  ) async {
    await _open(tester, status: 403);

    await tester.tap(find.text('Generate code'));
    await tester.pumpAndSettle();

    expect(find.text(_code), findsNothing);
    expect(find.textContaining('issue a reset code'), findsOneWidget);
    expect(
      find.text('Generate code'),
      findsOneWidget,
      reason: 'nothing was issued, so the action stays available to retry',
    );
  });
}
