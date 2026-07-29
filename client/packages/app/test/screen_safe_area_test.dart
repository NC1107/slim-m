// SPDX-License-Identifier: Apache-2.0
/// Every full-screen body keeps its content clear of the home indicator.
///
/// The rail and the composer got this and nothing else did, so on a notched
/// phone the last row of every settings, admin, onboarding and in-call screen
/// painted under the indicator. These pump each screen on a view that reports
/// real insets and assert on the bottom-most thing actually drawn, not on the
/// [SafeArea] itself: asserting on the widget that owns the inset is how the
/// rail's first attempt at this passed against the mistake it named.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/voice_roster.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/screens/admin/channel_overwrites_screen.dart';
import 'package:slimm_app/src/screens/admin/emoji_screen.dart';
import 'package:slimm_app/src/screens/admin/invites_screen.dart';
import 'package:slimm_app/src/screens/admin/reports_screen.dart';
import 'package:slimm_app/src/screens/admin/roles_screen.dart';
import 'package:slimm_app/src/screens/onboarding_screen.dart';
import 'package:slimm_app/src/screens/sign_in_screen.dart';
import 'package:slimm_app/src/screens/voice_screen.dart';
import 'package:slimm_app/src/screens/voice_settings_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';

/// An iPhone with a notch, in logical points.
const double _topInset = 59;
const double _bottomInset = 34;
const double _dpr = 3;
const Size _view = Size(390, 400);

const _tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

const _me = Me(
  id: 'user-1',
  username: 'admin',
  displayName: 'Admin',
  createdAt: 0,
  permissions: -1,
);

/// Every list endpoint these screens reach for, answered empty; the layout
/// question here is the same whether a list has rows in it or not. The voice
/// token is the one object body, since a call has to connect to have controls.
http.Client _emptyApi() => MockClient((request) async {
  final body = request.url.path.endsWith('/voice/token')
      ? jsonEncode({
          'url': 'wss://sfu.example.com',
          'room': 'channel-1',
          'token': 'jwt',
          'expires_at': 0,
          'can_publish': true,
        })
      : '[]';
  return http.Response(
    body,
    200,
    headers: const {'content-type': 'application/json'},
  );
});

/// The minimum [VoiceSession] the controller needs, connecting on join so the
/// in-call surface (and its bottom control bar) actually renders.
class _FakeSession implements VoiceSession {
  final _states = StreamController<VoiceSessionState>.broadcast();
  final _participants = StreamController<List<VoiceParticipant>>.broadcast();

  VoiceSessionState _state = VoiceSessionState.idle;

  @override
  bool deafened = false;

  @override
  VoiceSessionState get state => _state;

  @override
  Stream<VoiceSessionState> get states => _states.stream;

  @override
  List<VoiceParticipant> get participants => const [];

  @override
  Stream<List<VoiceParticipant>> get participantChanges => _participants.stream;

  @override
  Object? get lastError => null;

  @override
  VoiceDisconnect? get lastDisconnect => null;

  @override
  bool get screenShareNeedsSource => false;

  @override
  Future<List<ScreenShareSource>> screenShareSources() async => const [];

  @override
  Widget screenShareViewFor(String identity) =>
      SizedBox.shrink(key: Key('fake-share-view-$identity'));

  @override
  Future<void> join({
    required String url,
    required String token,
    bool microphoneEnabled = true,
  }) async {
    _state = VoiceSessionState.connected;
    _states.add(_state);
  }

  @override
  Future<void> leave() async {
    _state = VoiceSessionState.idle;
    _states.add(_state);
  }

  @override
  Future<bool> setMicrophoneEnabled(bool enabled) async => true;

  @override
  Future<ScreenShareOutcome> setScreenShareEnabled(
    bool enabled, {
    ScreenShareQuality quality = ScreenShareQuality.balanced,
    String? sourceId,
  }) async => enabled ? ScreenShareOutcome.started : ScreenShareOutcome.stopped;

  @override
  Future<bool> setDeafened(bool value) async => true;

  @override
  Future<void> dispose() async {
    await _states.close();
    await _participants.close();
  }
}

/// Pumps [home] on a view reporting notch and home-indicator insets.
Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override> overrides = const [],
  Size size = _view,
}) async {
  tester.view.physicalSize = size * _dpr;
  tester.view.devicePixelRatio = _dpr;
  tester.view.padding = FakeViewPadding(
    top: _topInset * _dpr,
    bottom: _bottomInset * _dpr,
  );
  tester.view.viewPadding = FakeViewPadding(
    top: _topInset * _dpr,
    bottom: _bottomInset * _dpr,
  );
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      sessionProvider.overrideWithValue(SessionStore(tokens: _tokens)),
      meProvider.overrideWith((ref) async => _me),
      apiProvider.overrideWith((ref) {
        final api = SlimmApi(
          baseUrl: Uri.parse('http://localhost:8080'),
          session: ref.watch(sessionProvider),
          httpClient: _emptyApi(),
        );
        ref.onDispose(api.close);
        return api;
      }),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildTheme(Brightness.light, AppTokens.light),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The whole point: nothing drawn may reach past the home indicator's edge.
void _expectClearOfIndicator(WidgetTester tester, Finder finder, String what) {
  expect(
    tester.getRect(finder).bottom,
    lessThanOrEqualTo(_view.height - _bottomInset),
    reason: '$what runs under the home indicator',
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('voice settings insets its list above the home indicator', (
    tester,
  ) async {
    await _pump(
      tester,
      const VoiceSettingsScreen(),
      overrides: [
        voiceControllerProvider.overrideWith(
          (ref) => VoiceController(ref, session: _FakeSession()),
        ),
        // The preview polls this every 15 seconds now that it shows who is
        // already in the call; without a stub the timer outlives the test.
        voiceRosterProvider.overrideWith(
          (ref, channelId) =>
              const Stream<List<VoiceRosterParticipant>>.empty(),
        ),
      ],
    );

    _expectClearOfIndicator(
      tester,
      find.byType(ListView),
      "voice settings' list",
    );
  });

  testWidgets('the invites list is inset', (tester) async {
    // Wider on purpose: the four-option expiry AppSegmentedControl.inline
    // overflows by 114px at 390, which is a separate defect from this inset.
    await _pump(tester, const InvitesScreen(), size: const Size(540, 400));

    _expectClearOfIndicator(tester, find.byType(ListView), 'the invite list');
  });

  testWidgets('the roles body is inset even when the list is empty', (
    tester,
  ) async {
    await _pump(tester, const RolesScreen());

    // The empty list renders its named empty state now, not a bare ListView;
    // the Center fills the body, so its box reports the inset.
    _expectClearOfIndicator(
      tester,
      find
          .ancestor(
            of: find.text('No roles yet. Create one with the + above.'),
            matching: find.byType(Center),
          )
          .first,
      'the roles empty state',
    );
  });

  testWidgets('the reports body is inset even when the queue is empty', (
    tester,
  ) async {
    await _pump(tester, const ReportsScreen());

    // The Center fills the body, so its box reports the inset; the text
    // inside it is centred and would pass either way.
    _expectClearOfIndicator(
      tester,
      find
          .ancestor(
            of: find.text('The queue is empty.'),
            matching: find.byType(Center),
          )
          .first,
      "the reports queue's empty state",
    );
  });

  testWidgets('the emoji list is inset', (tester) async {
    await _pump(tester, const EmojiScreen());

    _expectClearOfIndicator(tester, find.byType(ListView), 'the emoji list');
  });

  testWidgets('the channel overwrites list is inset', (tester) async {
    await _pump(tester, const ChannelOverwritesScreen());

    _expectClearOfIndicator(
      tester,
      find.byType(ListView),
      'the overwrites form',
    );
  });

  testWidgets('sign-in clears both the notch and the home indicator', (
    tester,
  ) async {
    await _pump(tester, const SignInScreen());

    final form = find.byType(SingleChildScrollView);
    expect(
      tester.getRect(form).top,
      greaterThanOrEqualTo(_topInset),
      reason: 'sign-in has no AppBar, so nothing else clears the notch',
    );
    _expectClearOfIndicator(tester, form, "sign-in's form");
  });

  testWidgets('onboarding clears both the notch and the home indicator', (
    tester,
  ) async {
    await _pump(tester, OnboardingScreen(onServerChosen: (_, __) {}));

    final body = find.byType(SingleChildScrollView);
    expect(
      tester.getRect(body).top,
      greaterThanOrEqualTo(_topInset),
      reason: 'onboarding has no AppBar, so nothing else clears the notch',
    );
    _expectClearOfIndicator(tester, body, "onboarding's entry list");
  });

  testWidgets('the in-call controls sit above the home indicator while their '
      'bar still paints to the edge', (tester) async {
    final container = await _pump(
      tester,
      const Scaffold(body: VoiceScreen(channelId: 'channel-1')),
      overrides: [
        voiceControllerProvider.overrideWith(
          (ref) => VoiceController(ref, session: _FakeSession()),
        ),
        // The preview polls this every 15 seconds now that it shows who is
        // already in the call; without a stub the timer outlives the test.
        voiceRosterProvider.overrideWith(
          (ref, channelId) =>
              const Stream<List<VoiceRosterParticipant>>.empty(),
        ),
      ],
    );
    await container.read(voiceControllerProvider.notifier).join('channel-1');
    await tester.pumpAndSettle();

    _expectClearOfIndicator(
      tester,
      find.byIcon(AppIcons.leaveCall),
      'the leave-call button',
    );

    // The other half: inset the bar itself and a base-coloured band appears
    // below it, so the decoration has to keep reaching the screen edge.
    final bar = find
        .ancestor(
          of: find.byIcon(AppIcons.leaveCall),
          matching: find.byType(DecoratedBox),
        )
        .last;
    expect(
      tester.getRect(bar).bottom,
      _view.height,
      reason: 'the control bar background must still reach the edge',
    );
  });
}
