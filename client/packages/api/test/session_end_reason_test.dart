// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Being signed out against your will is the one failure a person cannot
/// investigate for themselves: the app is back at sign-in and says nothing.
///
/// The server cannot help - it answers a rejected refresh with a bare 401 on
/// purpose, so a benign miss and a detected replay look identical to anyone
/// holding the token. What the client does know, and the server does not, is
/// whether the pair it presented was one this process had just rotated or one
/// it loaded from storage at launch. Those point at different causes:
///
/// - never rotated here: what was stored was already dead, so either a write
///   never landed or another instance spent it
/// - rotated seconds ago: this process raced itself or lost the response
///
/// These tests pin the distinction, because it is the whole value of the
/// message.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';

const _tokens = TokenPair(
  userId: 'me',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

SlimmApi _api(SessionStore session, http.Client client) => SlimmApi(
      baseUrl: Uri.parse('http://localhost:8080'),
      session: session,
      httpClient: client,
    );

http.Response _rejected() => http.Response('{}', 401);

http.Response _rotated() => http.Response(
      jsonEncode({
        'user_id': 'me',
        'access_token': 'access2',
        'refresh_token': 'refresh2',
        'access_expires_at': 0,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );

void main() {
  test('a rejection with no rotation this run blames what was stored',
      () async {
    final session = SessionStore(tokens: _tokens);
    final api = _api(session, MockClient((_) async => _rejected()));
    addTearDown(api.close);

    await expectLater(api.refresh(), throwsA(isA<UnauthorizedException>()));

    expect(session.isSignedIn, isFalse);
    expect(
      session.lastEndReason,
      contains('already spent at launch'),
      reason: 'nothing rotated here, so the stored pair is the suspect',
    );
  });

  test('a rejection after a rotation blames this run, and says how long after',
      () async {
    final session = SessionStore(tokens: _tokens);
    var calls = 0;
    final api = _api(
      session,
      MockClient((_) async => ++calls == 1 ? _rotated() : _rejected()),
    );
    addTearDown(api.close);

    await api.refresh();
    await expectLater(api.refresh(), throwsA(isA<UnauthorizedException>()));

    expect(session.lastEndReason, contains('after a rotation'));
    expect(
      session.lastEndReason,
      contains('persisted'),
      reason: 'whether the new pair reached storage is half the diagnosis',
    );
  });

  test('an ordinary sign-out is not reported as a rejection', () {
    final session = SessionStore(tokens: _tokens);
    session.clear();

    expect(session.lastEndReason, 'signed out');
    expect(session.lastEndReason, isNot(contains('rejected')));
  });

  test('every ending is announced, so the log cannot miss one', () async {
    final session = SessionStore(tokens: _tokens);
    final seen = <String>[];
    final sub = session.endings.listen(seen.add);
    addTearDown(sub.cancel);

    session.clear(reason: 'first');
    session.clear(reason: 'second');
    await Future<void>.delayed(Duration.zero);

    expect(seen, ['first', 'second']);
  });
}
