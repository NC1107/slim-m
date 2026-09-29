// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Buttons on a message and the two frames that concern them.
library;

import 'dart:convert';

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

const _buttons = [
  {
    'buttons': [
      {'label': 'Hit', 'style': 'primary', 'custom_id': 'hit'},
      {
        'label': 'Stand',
        'style': 'secondary',
        'custom_id': 'stand',
        'disabled': true,
      },
      {'label': 'Rules', 'style': 'link', 'url': 'https://example.com'},
    ],
  },
];

void main() {
  test('a message carries its rows of buttons', () {
    final message = Message.fromJson({
      'id': 'm1',
      'channel_id': 'c1',
      'seq': 1,
      'content': 'your move',
      'created_at': 1,
      'components': _buttons,
    });
    final row = message.components.single;
    expect(row.buttons.map((b) => b.label), ['Hit', 'Stand', 'Rules']);
    expect(row.buttons[0].style, ComponentButtonStyle.primary);
    expect(row.buttons[0].customId, 'hit');
    expect(row.buttons[1].disabled, isTrue);
    expect(row.buttons[2].style, ComponentButtonStyle.link);
    expect(row.buttons[2].customId, isNull);
    expect(row.buttons[2].url, 'https://example.com');
  });

  test('a message with no components field has none', () {
    final message = Message.fromJson({
      'id': 'm1',
      'channel_id': 'c1',
      'seq': 1,
      'content': 'hi',
      'created_at': 1,
    });
    expect(message.components, isEmpty);
  });

  test('an unknown style still renders as a pressable button', () {
    final button = MessageButton.fromJson({
      'label': 'x',
      'style': 'success',
      'custom_id': 'x',
    });
    expect(button.style, ComponentButtonStyle.secondary);
  });

  test('parses message.components, including a clear', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'message.components',
        'channel_id': 'c1',
        'message_id': 'm1',
        'components': <Object>[],
      }),
    );
    expect(event, isA<MessageComponentsChanged>());
    expect((event as MessageComponentsChanged).components, isEmpty);
    expect(event.messageId, 'm1');
  });

  test('parses interaction.answered', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'interaction.answered',
        'interaction_id': 'i1',
        'channel_id': 'c1',
        'message_id': 'm1',
      }),
    );
    expect(event, isA<InteractionAnswered>());
    expect((event as InteractionAnswered).interactionId, 'i1');
  });

  test('a components frame with no list is ignored, not thrown', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'message.components',
        'channel_id': 'c1',
        'message_id': 'm1',
      }),
    );
    expect(event, isNull);
  });
}
