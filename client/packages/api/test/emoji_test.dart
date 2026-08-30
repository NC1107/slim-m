// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Tests for custom emoji: the `emoji` tag, its model, and the byte fetch
/// that does not go through the JSON transport.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

Uri get _base => Uri.parse('http://localhost:8080');

TokenPair _tokens() => const TokenPair(
      userId: 'user-1',
      accessToken: 'access-1',
      refreshToken: 'refresh-1',
      accessExpiresAt: 0,
    );

Map<String, dynamic> _emojiJson({
  String id = 'emoji-1',
  String name = 'party_parrot',
  String? uploaderId = 'user-1',
  int createdAt = 1,
}) =>
    {
      'id': id,
      'name': name,
      'uploader_id': uploaderId,
      'created_at': createdAt,
    };

void main() {
  group('CustomEmoji', () {
    test('parses every field of the wire shape', () {
      final emoji = CustomEmoji.fromJson(_emojiJson(createdAt: 1700));
      expect(emoji.id, 'emoji-1');
      expect(emoji.name, 'party_parrot');
      expect(emoji.uploaderId, 'user-1');
      expect(emoji.createdAt, 1700);
    });

    test('a deleted uploader parses as null rather than throwing', () {
      final emoji = CustomEmoji.fromJson(_emojiJson(uploaderId: null));
      expect(emoji.uploaderId, isNull);
    });

    test('the shortcode is the name wrapped in colons, with no spaces', () {
      final emoji = CustomEmoji.fromJson(_emojiJson(name: 'big_smile'));
      expect(emoji.shortcode, ':big_smile:');
    });
  });

  group('listCustomEmoji', () {
    test('reads GET /emoji and parses the list in server order', () async {
      String? path;
      final api = SlimmApi(
        baseUrl: _base,
        session: SessionStore(tokens: _tokens()),
        httpClient: MockClient((request) async {
          path = request.url.path;
          return http.Response(
            jsonEncode([
              _emojiJson(id: 'a', name: 'first', createdAt: 1),
              _emojiJson(id: 'b', name: 'second', createdAt: 2),
            ]),
            200,
          );
        }),
      );
      final emoji = await api.listCustomEmoji();
      expect(path, '/emoji');
      expect(emoji.map((e) => e.name), ['first', 'second']);
    });

    test('an empty deployment parses as an empty list', () async {
      final api = SlimmApi(
        baseUrl: _base,
        session: SessionStore(tokens: _tokens()),
        httpClient: MockClient((_) async => http.Response('[]', 200)),
      );
      expect(await api.listCustomEmoji(), isEmpty);
    });
  });

  group('uploadCustomEmoji', () {
    test('sends the raw bytes as the body and the name in the query', () async {
      String? method;
      String? path;
      String? sentName;
      String? contentType;
      List<int>? sentBytes;
      final api = SlimmApi(
        baseUrl: _base,
        session: SessionStore(tokens: _tokens()),
        httpClient: MockClient((request) async {
          method = request.method;
          path = request.url.path;
          sentName = request.url.queryParameters['name'];
          contentType = request.headers['content-type'];
          sentBytes = request.bodyBytes;
          return http.Response(jsonEncode(_emojiJson()), 201);
        }),
      );
      final created = await api.uploadCustomEmoji(
        const [1, 2, 3],
        name: 'party_parrot',
      );
      expect(method, 'POST');
      expect(path, '/emoji');
      expect(sentName, 'party_parrot');
      expect(contentType, 'application/octet-stream');
      expect(sentBytes, [1, 2, 3]);
      expect(created.name, 'party_parrot');
    });

    test(
        'the name the server normalised to, not the one sent, is what comes '
        'back', () async {
      String? sentName;
      final api = SlimmApi(
        baseUrl: _base,
        session: SessionStore(tokens: _tokens()),
        httpClient: MockClient((request) async {
          sentName = request.url.queryParameters['name'];
          return http.Response(
            jsonEncode(_emojiJson(name: 'big_smile')),
            201,
          );
        }),
      );
      final created = await api.uploadCustomEmoji(
        const [1],
        name: 'Big Smile',
      );
      expect(sentName, 'Big Smile');
      expect(created.name, 'big_smile');
    });

    test('a name collision surfaces as ConflictException', () async {
      final api = SlimmApi(
        baseUrl: _base,
        session: SessionStore(tokens: _tokens()),
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({'error': 'an emoji with that name already exists'}),
              409,
            )),
      );
      expect(
        () => api.uploadCustomEmoji(const [1], name: 'taken'),
        throwsA(isA<ConflictException>()),
      );
    });

    test('missing MANAGE_SERVER surfaces as ForbiddenException', () async {
      final api = SlimmApi(
        baseUrl: _base,
        session: SessionStore(tokens: _tokens()),
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({'error': 'forbidden'}),
              403,
            )),
      );
      expect(
        () => api.uploadCustomEmoji(const [1], name: 'nope'),
        throwsA(isA<ForbiddenException>()),
      );
    });
  });

  group('deleteCustomEmoji', () {
    test('sends DELETE and tolerates the 204 that carries no body', () async {
      String? method;
      String? path;
      final api = SlimmApi(
        baseUrl: _base,
        session: SessionStore(tokens: _tokens()),
        httpClient: MockClient((request) async {
          method = request.method;
          path = request.url.path;
          return http.Response('', 204);
        }),
      );
      await api.deleteCustomEmoji('emoji-1');
      expect(method, 'DELETE');
      expect(path, '/emoji/emoji-1');
    });
  });

  group('fetchCustomEmojiImage', () {
    test('returns the raw bytes and the declared content type', () async {
      String? path;
      String? authorization;
      final api = SlimmApi(
        baseUrl: _base,
        session: SessionStore(tokens: _tokens()),
        httpClient: MockClient((request) async {
          path = request.url.path;
          authorization = request.headers['authorization'];
          return http.Response.bytes(
            [137, 80, 78, 71],
            200,
            headers: {'content-type': 'image/png'},
          );
        }),
      );
      final fetched = await api.fetchCustomEmojiImage('emoji-1');
      expect(path, '/emoji/emoji-1/image');
      expect(authorization, 'Bearer access-1');
      expect(fetched.bytes, [137, 80, 78, 71]);
      expect(fetched.contentType, 'image/png');
    });

    test('does not try to decode the bytes as JSON', () async {
      final api = SlimmApi(
        baseUrl: _base,
        session: SessionStore(tokens: _tokens()),
        httpClient: MockClient((_) async => http.Response.bytes(
              [0, 1, 2, 3],
              200,
              headers: {'content-type': 'image/webp'},
            )),
      );
      final fetched = await api.fetchCustomEmojiImage('emoji-1');
      expect(fetched.bytes, [0, 1, 2, 3]);
    });

    test('an unknown id surfaces as NotFoundException', () async {
      final api = SlimmApi(
        baseUrl: _base,
        session: SessionStore(tokens: _tokens()),
        httpClient: MockClient((_) async => http.Response(
              jsonEncode({'error': 'emoji not found'}),
              404,
            )),
      );
      expect(
        () => api.fetchCustomEmojiImage('nope'),
        throwsA(isA<NotFoundException>()),
      );
    });
  });
}
