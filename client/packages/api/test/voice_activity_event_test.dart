// SPDX-License-Identifier: Apache-2.0
/// Frame-parsing coverage for `voice.activity`: the live signal that closes
/// `docs/IMPLIED-GAPS.md` #2's in-app half - a DM (or voice channel) call
/// starting or ending while a bystander already has the app open.
library;

import 'dart:convert';

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  test('voice.activity decodes the channel id and nothing else', () {
    final event = ServerEvent.parse(jsonEncode({
      'type': 'voice.activity',
      'channel_id': 'c1',
    }));
    expect(event, isA<VoiceActivityChanged>());
    expect((event! as VoiceActivityChanged).channelId, 'c1');
  });

  test('a voice.activity frame missing channel_id is ignored, not a crash', () {
    expect(
      ServerEvent.parse(jsonEncode({'type': 'voice.activity'})),
      isNull,
    );
  });
}
