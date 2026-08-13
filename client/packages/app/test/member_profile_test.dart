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
import 'package:slimm_app/src/permissions.dart';
import 'package:slimm_app/src/providers/admin_providers.dart';
import 'package:slimm_app/src/providers/member_presence.dart';
import 'package:slimm_app/src/widgets/member_profile.dart';
import 'package:slimm_design_system/design_system.dart';

const _other = api.UserProfile(
  id: 'user-maya',
  username: 'maya',
  displayName: 'maya',
  createdAt: 0,
  roles: ['mod'],
  roleIds: ['role-mod'],
);

/// An hour out, so the badge's own arithmetic has something real to render.
final _timedOut = api.UserProfile(
  id: _other.id,
  username: _other.username,
  displayName: _other.displayName,
  createdAt: 0,
  roles: _other.roles,
  roleIds: _other.roleIds,
  timedOutUntil: DateTime.now()
      .add(const Duration(hours: 1))
      .millisecondsSinceEpoch,
);

Widget _harness(
  Widget child, {
  int permissions = 0,
  List<api.UserProfile> members = const [],
}) => ProviderScope(
  overrides: [
    myPermissionsProvider.overrideWithValue(permissions),
    membersProvider.overrideWith((ref) async => members),
  ],
  child: MaterialApp(
    theme: buildTheme(Brightness.light, AppTokens.light),
    home: Scaffold(body: child),
  ),
);

Widget _body(api.UserProfile profile, {String? mentionChannelName}) =>
    MemberProfileBody(
      profile: profile,
      status: AppPresence.online,
      mentionChannelName: mentionChannelName,
      compact: false,
      onDone: () {},
    );

void main() {
  testWidgets('a plain member gets the social verbs and block, nothing else', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_body(_other)));
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
    // No rights, so no section at all - not even its label.
    expect(find.text('MODERATION'), findsNothing);
    expect(find.text('Roles...'), findsNothing);
    expect(find.text('Remove from Space...'), findsNothing);
    expect(find.text('Time out for...'), findsNothing);
  });

  testWidgets('the mention row names its channel, and is absent without one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(_body(_other, mentionChannelName: 'general')),
    );
    await tester.pump();
    expect(find.text('Mention in #general'), findsOneWidget);

    await tester.pumpWidget(_harness(_body(_other)));
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

  group('moderation', () {
    testWidgets('each row appears only with the bit its route requires', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(_body(_other), permissions: Perm.kickMembers),
      );
      await tester.pump();
      expect(find.text('MODERATION'), findsOneWidget);
      expect(find.text('Time out for...'), findsOneWidget);
      expect(
        find.text('Remove from Space...'),
        findsNothing,
        reason: 'removing needs BAN_MEMBERS, which this caller lacks',
      );
      expect(find.text('Roles...'), findsNothing);

      await tester.pumpWidget(
        _harness(_body(_other), permissions: Perm.banMembers),
      );
      await tester.pump();
      expect(find.text('Remove from Space...'), findsOneWidget);
      expect(find.text('Time out for...'), findsNothing);

      await tester.pumpWidget(
        _harness(_body(_other), permissions: Perm.manageRoles),
      );
      await tester.pump();
      expect(find.text('Roles...'), findsOneWidget);
      expect(find.text('Time out for...'), findsNothing);
    });

    testWidgets('the durations are inline, so timing out is one tap', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(_body(_other), permissions: Perm.kickMembers),
      );
      await tester.pump();

      for (final label in ['5m', '1h', '24h', '7d']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });
  });

  group('the timed-out badge', () {
    testWidgets(
      'names exactly what is restricted, for anyone who can see them',
      (tester) async {
        await tester.pumpWidget(_harness(_body(_timedOut)));
        await tester.pump();

        expect(find.textContaining('Timed out'), findsOneWidget);
        expect(
          find.text(
            'Can read messages and view the canvas; '
            "can't draw, send messages, or join voice.",
          ),
          findsOneWidget,
        );
        expect(
          find.text('Lift'),
          findsNothing,
          reason: 'a member without the right sees the badge but no verb',
        );
      },
    );

    testWidgets('offers Lift to somebody who can actually lift it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(_body(_timedOut), permissions: Perm.kickMembers),
      );
      await tester.pump();
      expect(find.text('Lift'), findsOneWidget);
    });

    testWidgets(
      'replaces the duration chips rather than sitting beside them, and '
      'the section itself is absent once that is the only row it would '
      'have carried',
      (tester) async {
        await tester.pumpWidget(
          _harness(_body(_timedOut), permissions: Perm.kickMembers),
        );
        await tester.pump();

        expect(
          find.text('Time out for...'),
          findsNothing,
          reason:
              'the badge carries the countdown and its own undo; a second '
              'control would be two places to look for one fact',
        );
        expect(
          find.text('MODERATION'),
          findsNothing,
          reason:
              'KICK_MEMBERS alone offers only the now-suppressed chips row, '
              'so the section has nothing left to introduce - a bare '
              'header here was the bug shell.md and moderation.md both '
              'found independently',
        );
      },
    );

    testWidgets('is absent for a member who is not timed out', (tester) async {
      await tester.pumpWidget(
        _harness(_body(_other), permissions: Perm.kickMembers),
      );
      await tester.pump();
      expect(find.textContaining('Timed out'), findsNothing);
    });
  });
}
