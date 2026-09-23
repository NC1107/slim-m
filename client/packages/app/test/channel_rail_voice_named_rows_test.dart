// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Voice occupancy under a channel row used to be a strip of faces - avatars
/// only, no names, a count for who did not fit. It names people now, the
/// way a member pane does.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/widgets/channel_rail_channel_rows.dart';
import 'package:slimm_app/src/widgets/user_avatar.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import 'voice_controller_harness.dart';

const _tokens = api.TokenPair(
  userId: 'u-me',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 4102444800000,
);

final _channel = Channel(
  id: 'ch-1',
  name: 'General voice',
  kind: 'voice',
  createdAt: 0,
  position: 0,
  cursor: 0,
  lastReadSeq: 0,
  mentionedSeq: 0,
  slowModeSeconds: 0,
  isPersonalSpace: false,
);

VoiceParticipant _participant(
  String id,
  String name, {
  bool muted = false,
  bool screenSharing = false,
}) => VoiceParticipant(
  identity: id,
  name: name,
  isSpeaking: false,
  isMuted: muted,
  isLocal: false,
  isScreenSharing: screenSharing,
);

Widget _harness(VoiceState voice) {
  final apiClient = api.SlimmApi(
    baseUrl: Uri.parse('http://localhost:8080'),
    session: api.SessionStore(tokens: _tokens),
    httpClient: MockClient((_) async => http.Response('', 404)),
  );
  addTearDown(apiClient.close);
  return ProviderScope(
    overrides: [
      apiProvider.overrideWithValue(apiClient),
      voiceControllerProvider.overrideWith(
        (ref) => FixedVoiceController(ref, voice),
      ),
    ],
    child: MaterialApp(
      theme: buildTheme(Brightness.light, AppTokens.light),
      home: Scaffold(body: VoiceChannelRow(channel: _channel, selected: false)),
    ),
  );
}

void main() {
  testWidgets('each participant is named, not just pictured', (tester) async {
    await tester.pumpWidget(
      _harness(
        VoiceState(
          channelId: 'ch-1',
          state: VoiceSessionState.connected,
          participants: [
            _participant('u-me', 'Me'),
            _participant('u-priya', 'Priya'),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Priya'), findsOneWidget);
    expect(find.byType(AuthorAvatar), findsNWidgets(2));
  });

  testWidgets(
    'a muted participant carries the mic-off glyph on their own row',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          VoiceState(
            channelId: 'ch-1',
            state: VoiceSessionState.connected,
            participants: [
              _participant('u-me', 'Me'),
              _participant('u-priya', 'Priya', muted: true),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(AppIcons.micOff), findsOneWidget);
    },
  );

  testWidgets(
    'a screen-sharing participant carries the share glyph on their own row',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          VoiceState(
            channelId: 'ch-1',
            state: VoiceSessionState.connected,
            participants: [
              _participant('u-me', 'Me'),
              _participant('u-priya', 'Priya', screenSharing: true),
            ],
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(AppIcons.screenShare), findsOneWidget);
    },
  );

  testWidgets(
    'past eight, the list states a count rather than growing without bound',
    (tester) async {
      final participants = [
        for (var i = 0; i < 10; i++) _participant('u-$i', 'Person $i'),
      ];
      await tester.pumpWidget(
        _harness(
          VoiceState(
            channelId: 'ch-1',
            state: VoiceSessionState.connected,
            participants: participants,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AuthorAvatar), findsNWidgets(8));
      expect(find.text('+2 more'), findsOneWidget);
    },
  );
}
