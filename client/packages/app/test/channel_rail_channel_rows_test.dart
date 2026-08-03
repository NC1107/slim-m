// SPDX-License-Identifier: Apache-2.0
/// `ManagedChannelRow` used to compose the manage kebab as a sibling of the
/// channel row rather than inside it, so the row's own hover/press
/// highlight (painted by `AppListRow`'s tinted container) visibly stopped
/// short of the kebab and the row read as two separate pieces.
///
/// These tests pin the fix structurally (the kebab must be a descendant of
/// the row's own `AppListRow`, not a sibling beside it) rather than by
/// pixel, and pin the trap the fix has to avoid: `AppListRow.trailing`
/// already falls back to an unread dot, so handing the kebab to that same
/// slot would have silently dropped the dot on every unread channel.
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
import 'package:slimm_app/src/widgets/channel_rail_sections.dart';
import 'package:slimm_app/src/widgets/user_avatar.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

const _tokens = api.TokenPair(
  userId: 'u-me',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 4102444800000,
);

Channel _channel(
  String id,
  String name, {
  String kind = 'text',
  int cursor = 0,
  int lastReadSeq = 0,
}) => Channel(
  id: id,
  name: name,
  kind: kind,
  createdAt: 0,
  position: 0,
  cursor: cursor,
  lastReadSeq: lastReadSeq,
  isPersonalSpace: false,
);

/// [ChannelCategorySections] and [ManagedChannelRow] read no provider at all
/// (only the kebab's own `onPressed`, never invoked here, eventually would),
/// so a bare scope is enough for the first two tests below.
Widget _harness(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: Scaffold(body: child),
  ),
);

/// [VoiceChannelRow] renders an [AuthorAvatar] per participant, which does
/// read providers (a profile lookup, an avatar-bytes cache), so the voice
/// test below needs a real session and API client the way
/// `channel_rail_voice_roster_test.dart` already does for the same widget.
Widget _voiceHarness(Widget child) => ProviderScope(
  overrides: [
    sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
    apiProvider.overrideWith((ref) {
      final client = api.SlimmApi(
        baseUrl: Uri.parse('http://localhost:8080'),
        session: ref.watch(sessionProvider),
        httpClient: MockClient((_) async => http.Response('', 404)),
      );
      ref.onDispose(client.close);
      return client;
    }),
  ],
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets(
    'the kebab is a descendant of AppListRow, so the row highlight covers '
    'it rather than stopping short of it',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          ChannelCategorySections(
            channels: [_channel('c1', 'general')],
            categories: const [],
            selectedId: null,
            canManage: true,
            onReorder: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(AppListRow),
          matching: find.byIcon(AppIcons.moreVertical),
        ),
        findsOneWidget,
        reason:
            'a kebab composed as a sibling of AppListRow sits outside the '
            'AnimatedContainer that paints its hover/press tint',
      );
    },
  );

  testWidgets(
    'an unread channel keeps its unread dot once it also carries a kebab',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          ChannelCategorySections(
            channels: [_channel('c1', 'general', cursor: 5, lastReadSeq: 2)],
            categories: const [],
            selectedId: null,
            canManage: true,
            onReorder: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(AppListRow.unreadDotKey),
        findsOneWidget,
        reason:
            'AppListRow.trailing already falls back to the unread dot; '
            'routing the kebab through trailingExtra instead of trailing '
            'must leave that fallback untouched',
      );
      expect(
        find.descendant(
          of: find.byType(AppListRow),
          matching: find.byIcon(AppIcons.moreVertical),
        ),
        findsOneWidget,
        reason: 'the kebab must render alongside the dot, not replace it',
      );
    },
  );

  testWidgets(
    'a voice row with a kebab still centres it against the row alone, not '
    'the combined height of the row and its participant strip below',
    (tester) async {
      final channel = _channel('v1', 'General voice', kind: 'voice');
      await tester.pumpWidget(
        _voiceHarness(
          ManagedChannelRow(
            canManage: true,
            channel: channel,
            row: (kebab) => VoiceChannelRow(
              channel: channel,
              selected: false,
              trailingExtra: kebab,
              voice: const VoiceState(
                channelId: 'v1',
                state: VoiceSessionState.connected,
                participants: [
                  VoiceParticipant(
                    identity: 'u-1',
                    name: 'Alice',
                    isSpeaking: false,
                    isMuted: false,
                    isLocal: true,
                    isScreenSharing: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(AppListRow),
          matching: find.byIcon(AppIcons.moreVertical),
        ),
        findsOneWidget,
        reason:
            'the participant strip is a sibling of AppListRow, not part of '
            'it, so a kebab living inside the row is scoped to the row alone',
      );

      final rowBottom = tester.getBottomLeft(find.byType(AppListRow)).dy;
      final kebabCenter = tester
          .getCenter(find.byIcon(AppIcons.moreVertical))
          .dy;
      expect(
        kebabCenter,
        lessThan(rowBottom),
        reason:
            'the kebab must sit within the row itself, never floating '
            'against the combined row-plus-strip height below it',
      );
      expect(
        find.byType(AuthorAvatar),
        findsOneWidget,
        reason: 'the participant strip must still render beneath the row',
      );
    },
  );
}
