// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The wire half of shared code-block output: [ServerEvent.parse] for
/// `code_run.changed`, and [Message.fromJson] reading the `code_runs` field.
library;

import 'dart:convert';

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

Map<String, dynamic> _message(Map<String, dynamic> extra) => {
      'id': 'm1',
      'channel_id': 'c1',
      'author_id': 'a1',
      'author_display_name': 'Alice',
      'seq': 1,
      'content': '```js\nx\n```',
      'created_at': 0,
      'edited_at': null,
      ...extra,
    };

void main() {
  test('parses a code_run.changed frame into a CodeRun', () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'code_run.changed',
        'channel_id': 'c1',
        'message_id': 'm1',
        'block_index': 2,
        'module_id': 'code-exec',
        'command': 'run',
        'ok': true,
        'output': '42',
        'ran_by': 'u1',
        'ran_at': 1700000000000,
      }),
    );
    expect(event, isA<CodeRunChanged>());
    final changed = event as CodeRunChanged;
    expect(changed.messageId, 'm1');
    expect(changed.run.blockIndex, 2);
    expect(changed.run.ok, isTrue);
    expect(changed.run.output, '42');
    expect(changed.run.ranBy, 'u1');
  });

  test('a code_run.changed frame missing block_index is ignored, not thrown',
      () {
    final event = ServerEvent.parse(
      jsonEncode({
        'type': 'code_run.changed',
        'channel_id': 'c1',
        'message_id': 'm1',
      }),
    );
    expect(event, isNull);
  });

  test('Message.fromJson reads code_runs, with a null ran_by tolerated', () {
    final message = Message.fromJson(_message({
      'code_runs': [
        {
          'block_index': 0,
          'module_id': 'code-exec',
          'command': 'run',
          'ok': false,
          'output': 'boom',
          'ran_by': null,
          'ran_at': 1,
        },
      ],
    }));
    expect(message.codeRuns, hasLength(1));
    expect(message.codeRuns.first.ok, isFalse);
    expect(message.codeRuns.first.output, 'boom');
    expect(message.codeRuns.first.ranBy, isNull);
  });

  test('Message.fromJson defaults code_runs to empty when absent', () {
    expect(Message.fromJson(_message(const {})).codeRuns, isEmpty);
  });

  // Forward-compat: a frame kind from a future server is ignored, not thrown on, so a new module class does not break an older client. See decision 0022.
  test('an unknown frame type is ignored, not thrown', () {
    expect(
      ServerEvent.parse(jsonEncode({'type': 'surface.rendered', 'foo': 1})),
      isNull,
    );
  });
}
