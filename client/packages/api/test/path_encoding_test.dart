// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Regression tests for `client_transport.dart`'s single choke point on
/// request paths: a wire-supplied value (an emoji, here) must never decide
/// which resource a request reaches. Mirrors finding 9 of
/// docs/research/audit-2026-07-30/security.md, including its own worked
/// example (`../../account` resolving away the intended reactions path).
library;

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

Uri get _base => Uri.parse('https://chat.example');

TokenPair _tokens() => const TokenPair(
      userId: 'user-1',
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      accessExpiresAt: 0,
    );

/// An [SlimmApi] whose transport answers every call with 204 and reports
/// the [Uri] it was actually asked to send.
SlimmApi _apiCapturing(void Function(Uri) onRequest) => SlimmApi(
      baseUrl: _base,
      session: SessionStore(tokens: _tokens()),
      httpClient: MockClient((request) async {
        onRequest(request.url);
        return http.Response('', 204);
      }),
    );

void main() {
  group('path encoding at the transport choke point', () {
    test('a reaction emoji containing ../ stays under the reactions path',
        () async {
      Uri? seen;
      final api = _apiCapturing((uri) => seen = uri);
      await api.addReaction(messageId: 'm', emoji: '../../account');
      expect(seen!.path, startsWith('/messages/m/reactions/'));
      expect(seen!.path, isNot('/messages/account'));
    });

    test('a reaction emoji containing %2e%2e stays under the reactions path',
        () async {
      Uri? seen;
      final api = _apiCapturing((uri) => seen = uri);
      await api.addReaction(messageId: 'm', emoji: '%2e%2e');
      expect(seen!.path, startsWith('/messages/m/reactions/'));
      expect(seen!.path, isNot('/messages/account'));
    });

    test('a reaction emoji containing a slash stays under the reactions path',
        () async {
      Uri? seen;
      final api = _apiCapturing((uri) => seen = uri);
      await api.addReaction(messageId: 'm', emoji: 'thumb/pin');
      expect(seen!.path, startsWith('/messages/m/reactions/'));
    });

    test('a normal unicode emoji produces the same URL it produces today',
        () async {
      Uri? seen;
      final api = _apiCapturing((uri) => seen = uri);
      const emoji = '\u{1F44D}';
      await api.addReaction(messageId: 'm', emoji: emoji);
      final legacy = _base.replace(path: '/messages/m/reactions/$emoji');
      expect(seen, legacy);
    });

    test('a path containing a UUID is unchanged', () async {
      Uri? seen;
      final api = _apiCapturing((uri) => seen = uri);
      const messageId = '018f1a2e-1111-7000-8000-000000000000';
      await api.addReaction(messageId: messageId, emoji: 'x');
      final legacy = _base.replace(path: '/messages/$messageId/reactions/x');
      expect(seen, legacy);
    });

    test(
        'a channel id containing a colon (deployment shortcode style) '
        'is unchanged', () async {
      Uri? seen;
      final api = _apiCapturing((uri) => seen = uri);
      await api.addReaction(messageId: 'm', emoji: ':party:');
      final legacy = _base.replace(path: '/messages/m/reactions/:party:');
      expect(seen, legacy);
    });
  });
}
