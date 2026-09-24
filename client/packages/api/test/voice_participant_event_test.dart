// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Frame-parsing coverage for the LiveKit-webhook-sourced voice events:
/// `voice.participant_joined`, `voice.participant_left` and
/// `voice.screen_share_changed`. See
/// docs/decisions/0032-voice-participant-webhooks.md.
library;

import 'dart:convert';

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  test('voice.participant_joined decodes the channel and user id', () {
    final event = ServerEvent.parse(jsonEncode({
      'type': 'voice.participant_joined',
      'channel_id': 'c1',
      'user_id': 'u1',
    }));
    expect(event, isA<VoiceParticipantJoined>());
    final joined = event! as VoiceParticipantJoined;
    expect(joined.channelId, 'c1');
    expect(joined.userId, 'u1');
  });

  test('a voice.participant_joined frame missing user_id is ignored', () {
    expect(
      ServerEvent.parse(
        jsonEncode({'type': 'voice.participant_joined', 'channel_id': 'c1'}),
      ),
      isNull,
    );
  });

  test('voice.participant_left decodes the channel and user id', () {
    final event = ServerEvent.parse(jsonEncode({
      'type': 'voice.participant_left',
      'channel_id': 'c1',
      'user_id': 'u1',
    }));
    expect(event, isA<VoiceParticipantLeft>());
    final left = event! as VoiceParticipantLeft;
    expect(left.channelId, 'c1');
    expect(left.userId, 'u1');
  });

  test('voice.screen_share_changed decodes true and false alike', () {
    final started = ServerEvent.parse(jsonEncode({
      'type': 'voice.screen_share_changed',
      'channel_id': 'c1',
      'user_id': 'u1',
      'is_sharing_screen': true,
    }));
    expect(started, isA<VoiceScreenShareChanged>());
    expect((started! as VoiceScreenShareChanged).isSharingScreen, isTrue);

    final stopped = ServerEvent.parse(jsonEncode({
      'type': 'voice.screen_share_changed',
      'channel_id': 'c1',
      'user_id': 'u1',
      'is_sharing_screen': false,
    }));
    expect((stopped! as VoiceScreenShareChanged).isSharingScreen, isFalse);
  });

  test(
      'a voice.screen_share_changed frame missing is_sharing_screen is ignored',
      () {
    expect(
      ServerEvent.parse(jsonEncode({
        'type': 'voice.screen_share_changed',
        'channel_id': 'c1',
        'user_id': 'u1',
      })),
      isNull,
    );
  });

  test('an unrecognised voice event type is ignored, not a crash', () {
    expect(
      ServerEvent.parse(jsonEncode({
        'type': 'voice.something_future_versions_might_add',
        'channel_id': 'c1',
      })),
      isNull,
    );
  });
}
