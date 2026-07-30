// SPDX-License-Identifier: Apache-2.0
/// `setPresenceVisibility` survives a visibility value it has never heard of.
///
/// Its own file rather than another case in `new_routes_test.dart`: that one
/// is at its allowlisted ceiling, and its allowlist entry already says it is
/// "the 21 routes of PR #36 in one file, named for that pull request rather
/// than for anything it covers". Growing it further to hold a test about
/// something else would deepen exactly the problem the entry records.
///
/// The fallback is `hidden`, and the direction is the whole point. This is
/// the caller's own choice echoed back after a `PATCH`, so a value the client
/// cannot decode must not resolve toward the more public state: telling
/// somebody they are visible when they are not is the one misreading this
/// codebase treats as unacceptable, and it is why `PresenceChanged` carries
/// no status at all and every surface derives one per viewer instead.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

final _base = Uri.parse('http://localhost:8080');

TokenPair _tokens() => const TokenPair(
      userId: 'u1',
      accessToken: 'access',
      refreshToken: 'refresh',
      accessExpiresAt: 0,
    );

void main() {
  test('an unrecognised visibility reads as hidden, not a throw', () async {
    final api = SlimmApi(
      baseUrl: _base,
      session: SessionStore(tokens: _tokens()),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'visibility': 'invisible'}),
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(api.close);

    expect(
      await api.setPresenceVisibility(PresenceVisibility.online),
      PresenceVisibility.hidden,
    );
  });

  /// The recognised values must still round-trip, or the tolerant parse could
  /// be answering `hidden` for everything and the test above would not know.
  test('a recognised visibility still reads as itself', () async {
    for (final visibility in PresenceVisibility.values) {
      final api = SlimmApi(
        baseUrl: _base,
        session: SessionStore(tokens: _tokens()),
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({'visibility': visibility.name}),
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(api.close);
      expect(
        await api.setPresenceVisibility(PresenceVisibility.online),
        visibility,
      );
    }
  });
}
