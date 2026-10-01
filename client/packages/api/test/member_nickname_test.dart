// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// `PUT` and `DELETE /members/{userId}/nickname`, and the two profile fields
/// that report a nickname: decision 0053.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

final _base = Uri.parse('http://localhost:8080');

SlimmApi _api(Future<http.Response> Function(http.Request) handler) => SlimmApi(
      baseUrl: _base,
      session: SessionStore(
        tokens: const TokenPair(
          userId: 'u1',
          accessToken: 'access',
          refreshToken: 'refresh',
          accessExpiresAt: 0,
        ),
      ),
      httpClient: MockClient(handler),
    );

void main() {
  test('setMemberNickname puts the name and clearMemberNickname deletes it',
      () async {
    final seen = <String>[];
    final api = _api((request) async {
      seen.add('${request.method} ${request.url.path} ${request.body}');
      return http.Response('', 204);
    });
    await api.setMemberNickname(userId: 'u2', nickname: 'House DJ');
    await api.clearMemberNickname('u2');
    expect(seen, [
      'PUT /members/u2/nickname ${jsonEncode({'nickname': 'House DJ'})}',
      'DELETE /members/u2/nickname ',
    ]);
  });

  test('a profile reads its nickname and the account name beside it', () {
    final profile = UserProfile.fromJson({
      'id': 'u2',
      'username': 'nia',
      'display_name': 'House DJ',
      'nickname': 'House DJ',
      'account_display_name': 'Nia',
      'created_at': 1,
    });
    expect(profile.displayName, 'House DJ');
    expect(profile.nickname, 'House DJ');
    expect(profile.accountDisplayName, 'Nia');
  });

  test('a server before nicknames leaves both null', () {
    final profile = UserProfile.fromJson({
      'id': 'u2',
      'username': 'nia',
      'display_name': 'Nia',
      'created_at': 1,
    });
    expect(profile.nickname, isNull);
    expect(profile.accountDisplayName, isNull);
  });
}
