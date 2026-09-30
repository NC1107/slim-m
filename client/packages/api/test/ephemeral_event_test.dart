// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// [ServerEvent.parse] for `message.ephemeral`: a bot's private answer.
library;

import 'dart:convert';

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  test('parses a well-formed message.ephemeral frame', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'message.ephemeral',
        'channel_id': 'c1',
        'message': {
          'id': 'e1',
          'channel_id': 'c1',
          'author_id': 'b1',
          'author_display_name': 'Helper',
          'content': 'you have 500 chips',
          'in_reply_to_id': 'm1',
          'created_at': 12,
        },
      }),
    );
    expect(event, isA<MessageEphemeral>());
    final ephemeral = event as MessageEphemeral;
    expect(ephemeral.channelId, 'c1');
    expect(ephemeral.message.id, 'e1');
    expect(ephemeral.message.authorDisplayName, 'Helper');
    expect(ephemeral.message.content, 'you have 500 chips');
    expect(ephemeral.message.inReplyToId, 'm1');
  });

  test('a frame with no message body is ignored, not thrown', () {
    final event = ServerEvent.parse(
      jsonEncode({'type': 'message.ephemeral', 'channel_id': 'c1'}),
    );
    expect(event, isNull);
  });

  test('a message.ephemeral frame carries its files and embeds', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'message.ephemeral',
        'channel_id': 'c1',
        'message': {
          'id': 'e1',
          'channel_id': 'c1',
          'author_id': 'b1',
          'author_display_name': 'Helper',
          'content': '',
          'in_reply_to_id': 'm1',
          'created_at': 12,
          'attachments': [
            {
              'id': 'f1',
              'filename': 'a.png',
              'content_type': 'image/png',
              'size': 3,
            },
          ],
          'embeds': [
            {'title': 'Balance', 'fields': <dynamic>[]},
          ],
        },
      }),
    );
    final message = (event as MessageEphemeral).message;
    expect(message.attachments.single.filename, 'a.png');
    expect(message.embeds.single.title, 'Balance');
  });

  test('a report subject round-trips its wire name', () {
    expect(ReportSubject.ephemeralMessage.wire, 'ephemeral_message');
    expect(
      ReportSubject.parse('ephemeral_message'),
      ReportSubject.ephemeralMessage,
    );
    expect(ReportSubject.parse('something_new'), ReportSubject.user);
  });
}
