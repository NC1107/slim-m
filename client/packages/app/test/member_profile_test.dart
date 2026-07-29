// SPDX-License-Identifier: Apache-2.0
/// The profile popover's composition rule: a section you have no rights or
/// context for is *absent*, never present-and-disabled. That is what keeps a
/// plain member's popover to a couple of verbs instead of a wall of greyed
/// rows, and it is the rule most likely to erode as sections are added.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/widgets/member_profile.dart';
import 'package:slimm_design_system/design_system.dart';

const _other = api.UserProfile(
  id: 'user-maya',
  username: 'maya',
  displayName: 'maya',
  createdAt: 0,
  roles: ['mod'],
);

Widget _harness(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('a plain member gets the social verbs and block, nothing else', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        MemberProfileBody(
          profile: _other,
          status: AppPresence.online,
          compact: false,
          onDone: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('maya'), findsOneWidget);
    expect(find.text('online'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Block'), findsOneWidget);

    // No call in progress, so nothing about hearing them.
    expect(
      find.text('Mute for me'),
      findsNothing,
      reason: 'the call section belongs to a shared call, not to a person',
    );
  });

  testWidgets('the mention row names its channel, and is absent without one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        MemberProfileBody(
          profile: _other,
          status: AppPresence.online,
          mentionChannelName: 'general',
          compact: false,
          onDone: () {},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Mention in #general'), findsOneWidget);

    await tester.pumpWidget(
      _harness(
        MemberProfileBody(
          profile: _other,
          status: AppPresence.online,
          compact: false,
          onDone: () {},
        ),
      ),
    );
    await tester.pump();
    expect(
      find.textContaining('Mention in'),
      findsNothing,
      reason: 'no channel in view means no channel to mention them in',
    );
  });

  testWidgets('presence is a word beside its dot, never the dot alone', (
    tester,
  ) async {
    for (final (status, word) in const [
      (AppPresence.online, 'online'),
      (AppPresence.away, 'away'),
      (AppPresence.dnd, 'do not disturb'),
      (AppPresence.offline, 'offline'),
      (AppPresence.hidden, 'appearing offline'),
    ]) {
      await tester.pumpWidget(
        _harness(
          MemberProfileBody(
            profile: _other,
            status: status,
            compact: false,
            onDone: () {},
          ),
        ),
      );
      await tester.pump();
      expect(find.text(word), findsOneWidget, reason: '$status');
      expect(find.byType(AppStatusDot), findsWidgets, reason: '$status');
    }
  });

  testWidgets('the compact presentation carries the same rows', (tester) async {
    await tester.pumpWidget(
      _harness(
        MemberProfileBody(
          profile: _other,
          status: AppPresence.online,
          mentionChannelName: 'general',
          compact: true,
          onDone: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Mention in #general'), findsOneWidget);
    expect(find.text('Block'), findsOneWidget);
  });
}
