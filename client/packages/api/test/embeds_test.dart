// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
import 'package:test/test.dart';
import 'package:slimm_api/api.dart' as api;

Map<String, dynamic> _baseMessage() => {
      'id': 'm1',
      'channel_id': 'c1',
      'author_id': 'u1',
      'author_display_name': 'ci-bot',
      'seq': 1,
      'content': 'a build result',
      'created_at': 0,
      'edited_at': null,
    };

void main() {
  test('Message.fromJson reads an embed with a field and an accent', () {
    final message = api.Message.fromJson({
      ..._baseMessage(),
      'embeds': [
        {
          'title': 'Build failed',
          'description': 'main is red',
          'accent': 'red',
          'author_name': 'ci',
          'fields': [
            {'name': 'Job', 'value': 'server-ci', 'inline': true},
          ],
          'footer_text': 'slim-m ci',
          'timestamp': 1700000000000,
          'image_token': 'tok-1',
          'thumbnail_token': null,
        },
      ],
    });

    expect(message.embeds, hasLength(1));
    final embed = message.embeds.single;
    expect(embed.title, 'Build failed');
    expect(embed.accent, api.EmbedAccent.red);
    expect(embed.fields.single.name, 'Job');
    expect(embed.fields.single.inline, isTrue);
    expect(embed.imageToken, 'tok-1');
    expect(embed.thumbnailToken, isNull);
  });

  test('Message.fromJson defaults embeds to empty when absent', () {
    expect(api.Message.fromJson(_baseMessage()).embeds, isEmpty);
  });

  test('an unrecognised accent decodes to null rather than throwing', () {
    final message = api.Message.fromJson({
      ..._baseMessage(),
      'embeds': [
        {'accent': 'chartreuse'},
      ],
    });
    expect(message.embeds.single.accent, isNull);
  });
}
