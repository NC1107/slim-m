// SPDX-License-Identifier: Apache-2.0
/// Ejecting somebody from the call you share with them: the member profile
/// popover's one caller of `kickVoiceParticipant`.
///
/// The row only exists while `MemberProfileBody` can compute an actual room
/// to evict from - `inCallTogether` plus a channel id - so this drives a real
/// `VoiceController` through a real `join` and a fake session's participant
/// stream, rather than asserting on a permission bit alone the way the rest
/// of the moderation suite does.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart' show GoRouter, GoRoute;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/permissions.dart';
import 'package:slimm_app/src/providers/admin_providers.dart';
import 'package:slimm_app/src/providers/member_presence.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/widgets/member_profile.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';

import 'voice_controller_harness.dart' show FakeSession, tokens;

const _channelId = 'channel-shared';

const _other = api.UserProfile(
  id: 'user-maya',
  username: 'maya',
  displayName: 'maya',
  createdAt: 0,
);

/// A container with a real [VoiceController] wired to [session], so a test
/// can drive it into [_channelId] and record every request it sends.
///
/// [selfProfile], when given, makes [_other] the caller's own profile - the
/// "never offered against yourself" case - by overriding [meProvider] rather
/// than by nesting a second [ProviderScope], which would leave the eject
/// button's own `ProviderScope.containerOf` reading a container this test
/// cannot see requests through.
({ProviderContainer container, List<String> requests, FakeSession session})
_wire({int permissions = 0, api.Me? selfProfile}) {
  final requests = <String>[];
  final session = FakeSession();
  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: tokens)),
      myPermissionsProvider.overrideWithValue(permissions),
      membersProvider.overrideWith((ref) async => [_other]),
      if (selfProfile != null)
        meProvider.overrideWith((ref) async => selfProfile),
      apiProvider.overrideWith((ref) {
        final client = api.SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: MockClient((request) async {
            requests.add('${request.method} ${request.url.path}');
            if (request.url.path.endsWith('/voice/token')) {
              return http.Response(
                jsonEncode({
                  'url': 'wss://sfu.example.com',
                  'room': _channelId,
                  'token': 'jwt',
                  'expires_at': 0,
                  'can_publish': true,
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response('', 204);
          }),
        );
        ref.onDispose(client.close);
        return client;
      }),
      voiceControllerProvider.overrideWith(
        (ref) => VoiceController(ref, session: session),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, requests: requests, session: session);
}

/// Joins [_channelId] for real (a mocked token round trip) and then drives
/// the fake session's own streams, the shape every other suite touching
/// [FakeSession] uses to reach `connected` - `join()` alone never does, since
/// the transition is read off `VoiceSession.states`, not the return value.
Future<void> _joinShared(
  WidgetTester tester,
  ProviderContainer container,
  FakeSession session,
) async {
  await container.read(voiceControllerProvider.notifier).join(_channelId);
  session.emitState(VoiceSessionState.connected);
  session.emitParticipants([
    VoiceParticipant(
      identity: _other.id,
      name: _other.displayName,
      isSpeaking: false,
      isMuted: false,
      isLocal: false,
      isScreenSharing: false,
    ),
  ]);
  await tester.pump();
}

/// The one test that opens the real [showMemberProfile] sits its ambient
/// reduce-motion `MediaQuery` (needed for the pop's disposal to land within
/// one frame, same as `member_profile_dismiss_test.dart`) directly above
/// `MaterialApp.router`, which also zeroes what `MediaQuery.sizeOf` reports
/// and so forces the compact bottom-sheet path; this gives that sheet real
/// room so the call section's extra rows do not overflow it.
void _giveCompactSheetRoom(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Widget _body() => MemberProfileBody(
  profile: _other,
  status: AppPresence.online,
  compact: false,
  onDone: () {},
);

/// Reduce motion is forced on: [MemberProfileHeader] renders the shared
/// avatar with `speaking: inCallTogether`, which mounts a perpetually
/// pulsing `AppSpeakingRing` the moment a call is joined, and a real
/// repeating ticker never lets `pumpAndSettle` settle.
Widget _harness(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: Scaffold(body: child),
        ),
      ),
    );

void main() {
  testWidgets('absent without KICK_MEMBERS, even while sharing the call', (
    tester,
  ) async {
    final wired = _wire();
    await tester.pumpWidget(_harness(wired.container, _body()));
    await _joinShared(tester, wired.container, wired.session);

    expect(
      find.text('Mute for me'),
      findsOneWidget,
      reason:
          'the call section itself must render, or this test proves '
          'nothing about the moderation row specifically',
    );
    expect(find.text('Eject from call...'), findsNothing);
    // Clears the heartbeat timer a connected call now keeps running.
    await wired.container.read(voiceControllerProvider.notifier).leave();
  });

  testWidgets('absent with KICK_MEMBERS while no call is shared', (
    tester,
  ) async {
    final wired = _wire(permissions: Perm.kickMembers);
    await tester.pumpWidget(_harness(wired.container, _body()));
    await tester.pump();

    expect(find.text('Eject from call...'), findsNothing);
  });

  testWidgets('never offered against yourself', (tester) async {
    final wired = _wire(
      permissions: Perm.kickMembers,
      selfProfile: api.Me(
        id: _other.id,
        username: _other.username,
        displayName: _other.displayName,
        createdAt: 0,
        permissions: Perm.kickMembers,
      ),
    );
    await tester.pumpWidget(_harness(wired.container, _body()));
    await _joinShared(tester, wired.container, wired.session);

    expect(find.text('Eject from call...'), findsNothing);
    await wired.container.read(voiceControllerProvider.notifier).leave();
  });

  testWidgets('appears once both the bit and a shared call are true', (
    tester,
  ) async {
    final wired = _wire(permissions: Perm.kickMembers);
    await tester.pumpWidget(_harness(wired.container, _body()));
    await _joinShared(tester, wired.container, wired.session);

    expect(find.text('Eject from call...'), findsOneWidget);
    await wired.container.read(voiceControllerProvider.notifier).leave();
  });

  testWidgets('names the room, not a ban, and confirming reaches the API', (
    tester,
  ) async {
    final wired = _wire(permissions: Perm.kickMembers);
    await tester.pumpWidget(_harness(wired.container, _body()));
    await _joinShared(tester, wired.container, wired.session);

    await tester.tap(find.text('Eject from call...'));
    await tester.pumpAndSettle();

    expect(find.text('Eject maya from this call?'), findsOneWidget);
    expect(find.textContaining('Nothing stops them rejoining'), findsOneWidget);

    await tester.tap(find.text('Eject'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      wired.requests,
      contains(
        'POST /channels/$_channelId/voice/participants/${_other.id}/kick',
      ),
    );
    await wired.container.read(voiceControllerProvider.notifier).leave();
  });

  testWidgets('cancelling sends nothing', (tester) async {
    final wired = _wire(permissions: Perm.kickMembers);
    await tester.pumpWidget(_harness(wired.container, _body()));
    await _joinShared(tester, wired.container, wired.session);

    await tester.tap(find.text('Eject from call...'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(wired.requests.where((r) => r.contains('/kick')), isEmpty);
    await wired.container.read(voiceControllerProvider.notifier).leave();
  });

  testWidgets(
    'reaches the API rather than throwing past a real dismiss - the same '
    "class of bug '_remove' guards against, since '_eject' shares its shape",
    (tester) async {
      _giveCompactSheetRoom(tester);

      final wired = _wire(permissions: Perm.kickMembers);
      // Joined on the container itself, before any widget is pumped.
      await wired.container
          .read(voiceControllerProvider.notifier)
          .join(_channelId);
      wired.session.emitState(VoiceSessionState.connected);
      wired.session.emitParticipants([
        VoiceParticipant(
          identity: _other.id,
          name: _other.displayName,
          isSpeaking: false,
          isMuted: false,
          isLocal: false,
          isScreenSharing: false,
        ),
      ]);

      final router = GoRouter(
        initialLocation: '/start',
        routes: [
          GoRoute(
            path: '/start',
            builder: (context, state) => Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showMemberProfile(
                    context,
                    ref,
                    profile: _other,
                    status: AppPresence.online,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: wired.container,
          child: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: MaterialApp.router(
              theme: buildTheme(Brightness.light, AppTokens.light),
              routerConfig: router,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Eject from call...'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Eject'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(tester.takeException(), isNull);
      expect(
        wired.requests,
        contains(
          'POST /channels/$_channelId/voice/participants/${_other.id}/kick',
        ),
      );
      await wired.container.read(voiceControllerProvider.notifier).leave();
    },
  );
}
