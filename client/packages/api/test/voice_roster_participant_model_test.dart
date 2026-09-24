// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Wire-parsing coverage for `is_sharing_screen`/`has_video` on
/// `VoiceRosterParticipant`, added alongside the live voice events in
/// docs/decisions/0032-voice-participant-webhooks.md.
library;

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  test('is_sharing_screen and has_video decode when present', () {
    final participant = VoiceRosterParticipant.fromJson({
      'user_id': 'u1',
      'display_name': 'Alice',
      'is_sharing_screen': true,
      'has_video': true,
    });
    expect(participant.isSharingScreen, isTrue);
    expect(participant.hasVideo, isTrue);
  });

  test('both default to false against an older server that omits them', () {
    final participant = VoiceRosterParticipant.fromJson({
      'user_id': 'u1',
      'display_name': 'Alice',
    });
    expect(participant.isSharingScreen, isFalse);
    expect(participant.hasVideo, isFalse);
  });
}
