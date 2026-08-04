// SPDX-License-Identifier: Apache-2.0
/// Tests that the share control never claims a share that is not happening,
/// applies the quality already chosen in Voice settings without asking
/// again, and cannot be re-entered by a fast double-tap while it is still
/// enumerating sources.
///
/// On iOS, asking to share only asks the system to offer a broadcast picker.
/// Capture runs in a separate ReplayKit extension process, and nothing is
/// published until the user starts the broadcast there. A control that lights
/// up on the request is describing something nobody can see, which is what the
/// owner reported as screen share doing nothing.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_app/src/screens/voice_call_controls.dart';
import 'package:slimm_app/src/screens/voice_settings_screen.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';

/// Mirrors `voice_settings_screen.dart`'s own private key: that screen's
/// `VoiceSettingsController` is the real one under test here too, loaded from
/// [SharedPreferences] exactly as it is in the app, rather than swapped for a
/// fake - the bug this covers is that a saved value was never read back.
const _qualityKey = 'slimm.voice.screen_share_quality';

/// The controls take their [VoiceState] as a parameter, so the session behind
/// the controller never has to reach any of these states itself.
class _InertSession implements VoiceSession {
  _InertSession({
    bool needsSource = false,
    Future<List<ScreenShareSource>>? sources,
    ScreenShareOutcome outcome = ScreenShareOutcome.started,
    bool sourcePickerUseful = true,
  }) : _needsSource = needsSource,
       _sources = sources ?? Future.value(const []),
       _outcome = outcome,
       screenShareSourcePickerUseful = sourcePickerUseful;

  final bool _needsSource;
  final Future<List<ScreenShareSource>> _sources;

  @override
  final bool screenShareSourcePickerUseful;

  /// Desktop starts sharing outright; `pendingBroadcast` is the iOS-only
  /// shape and is what would arm `VoiceController`'s 30-second broadcast
  /// deadline timer, which a test tapping share has to either not trigger or
  /// clean up before its own body ends.
  final ScreenShareOutcome _outcome;

  /// How many times a source list was actually requested, so a test can
  /// assert a fast double-tap only enumerated once.
  int sourceFetchCount = 0;

  /// Every call `setScreenShareEnabled` received, in order, so a test can
  /// assert on the quality it was actually given rather than only on the
  /// outcome.
  final List<({bool enabled, ScreenShareQuality quality, String? sourceId})>
  screenShareCalls = [];

  @override
  bool get supportsParticipantVolume => true;

  final Map<String, double> _volumes = {};

  @override
  double volumeFor(String identity) => _volumes[identity] ?? 1.0;

  @override
  Future<void> setVolumeFor(String identity, double volume) async {
    _volumes[identity] = volume.clamp(0.0, 2.0);
  }

  final _states = StreamController<VoiceSessionState>.broadcast();
  final _participants = StreamController<List<VoiceParticipant>>.broadcast();

  @override
  bool deafened = false;

  @override
  VoiceSessionState get state => VoiceSessionState.connected;

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
  bool get screenShareNeedsSource => _needsSource;

  @override
  Future<List<ScreenShareSource>> screenShareSources() {
    sourceFetchCount += 1;
    return _sources;
  }

  final Set<String> _locallyMuted = {};

  @override
  bool isLocallyMuted(String identity) => _locallyMuted.contains(identity);

  @override
  Future<void> setLocallyMuted(String identity, bool muted) async {
    muted ? _locallyMuted.add(identity) : _locallyMuted.remove(identity);
  }

  @override
  Widget screenShareViewFor(String identity) =>
      SizedBox.shrink(key: Key('fake-share-view-$identity'));

  @override
  Widget cameraViewFor(String identity) =>
      SizedBox.shrink(key: Key('fake-camera-view-$identity'));

  /// Every camera-switching call this session received, in order, so a test
  /// can assert on how the control chose between flipping and picking.
  final List<String> cameraSwitchCalls = [];

  @override
  bool canFlipCamera = false;

  @override
  bool cameraNeedsSelection = false;

  List<CameraDevice> cameraDeviceList = const [];

  @override
  Future<List<CameraDevice>> cameraDevices() async => cameraDeviceList;

  @override
  Future<bool> flipCamera() async {
    cameraSwitchCalls.add('flip');
    return true;
  }

  @override
  Future<bool> selectCameraDevice(CameraDevice device) async {
    cameraSwitchCalls.add('select:${device.id}');
    return true;
  }

  @override
  Future<void> join({
    required String url,
    required String token,
    bool microphoneEnabled = true,
    bool cameraEnabled = false,
  }) async {}

  @override
  Future<void> leave() async {}

  @override
  Future<bool> setMicrophoneEnabled(bool enabled) async => true;

  /// Every call `setCameraEnabled` received, so a test can assert the
  /// toggle button actually reached the session.
  final List<bool> setCameraCalls = [];

  @override
  Future<bool> setCameraEnabled(bool enabled) async {
    setCameraCalls.add(enabled);
    return true;
  }

  @override
  Future<bool> setDeafened(bool value) async => true;

  @override
  Future<ScreenShareOutcome> setScreenShareEnabled(
    bool enabled, {
    ScreenShareQuality quality = ScreenShareQuality.balanced,
    String? sourceId,
  }) async {
    screenShareCalls.add((
      enabled: enabled,
      quality: quality,
      sourceId: sourceId,
    ));
    return _outcome;
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _participants.close();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpControls(
    WidgetTester tester,
    VoiceState voice, {
    _InertSession? session,
  }) async {
    final container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        voiceControllerProvider.overrideWith(
          (ref) => VoiceController(ref, session: session ?? _InertSession()),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(Brightness.light, AppTokens.light),
          home: Scaffold(
            body: CallControls(
              controller: container.read(voiceControllerProvider.notifier),
              voice: voice,
            ),
          ),
        ),
      ),
    );
    // pump, not pumpAndSettle: the pending state runs a progress indicator,
    // which never settles.
    await tester.pump();
    return container;
  }

  testWidgets('a share awaiting a broadcast reads as waiting, not as on', (
    tester,
  ) async {
    await pumpControls(
      tester,
      const VoiceState(
        state: VoiceSessionState.connected,
        awaitingBroadcast: true,
      ),
    );

    expect(find.byIcon(AppIcons.screenShare), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        'Waiting for you to start the broadcast. Tap to cancel.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a live share reads as sharing', (tester) async {
    await pumpControls(
      tester,
      const VoiceState(state: VoiceSessionState.connected, screenSharing: true),
    );

    expect(find.byIcon(AppIcons.screenShare), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.bySemanticsLabel('Stop sharing'), findsOneWidget);
  });

  testWidgets(
    'sharing applies the quality already saved in Voice settings, asking nothing',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        _qualityKey: ScreenShareQuality.crisp.name,
      });
      final session = _InertSession();
      final container = await pumpControls(
        tester,
        const VoiceState(state: VoiceSessionState.connected),
        session: session,
      );

      // Warms the async load, or the tap would only see the default state.
      container.read(voiceSettingsControllerProvider);
      await container.read(preferencesProvider.future);
      await tester.pump();
      expect(
        container.read(voiceSettingsControllerProvider).screenShareQuality,
        ScreenShareQuality.crisp,
      );

      await tester.tap(find.byTooltip('Share a screen'));
      await tester.pumpAndSettle();

      // The setting is authoritative, not a pre-fill for one more question.
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(session.screenShareCalls, hasLength(1));
      expect(session.screenShareCalls.single.quality, ScreenShareQuality.crisp);
    },
  );

  testWidgets('a fast double-tap on share enumerates sources only once', (
    tester,
  ) async {
    final sourcesCompleter = Completer<List<ScreenShareSource>>();
    final session = _InertSession(
      needsSource: true,
      sources: sourcesCompleter.future,
    );
    await pumpControls(
      tester,
      const VoiceState(state: VoiceSessionState.connected),
      session: session,
    );

    final shareButton = find.byTooltip('Share a screen');
    // Both taps land before the source lookup they raced to start answers.
    await tester.tap(shareButton);
    await tester.pump();
    await tester.tap(shareButton);
    await tester.pump();

    sourcesCompleter.complete(const [
      ScreenShareSource(id: '1', name: 'Screen 1'),
      ScreenShareSource(id: '2', name: 'Screen 2'),
    ]);
    await tester.pumpAndSettle();

    expect(session.sourceFetchCount, 1);
    // The sheet's own body copy: its tooltip is also "Share a screen".
    expect(
      find.text('Everyone in the call will see it until you stop sharing.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'on Linux the portal picks, so this app never opens a second picker',
    (tester) async {
      final session = _InertSession(
        needsSource: true,
        sources: Future.value(const [
          ScreenShareSource(id: '1', name: 'Screen 1'),
          ScreenShareSource(id: '2', name: 'Screen 2'),
        ]),
        sourcePickerUseful: false,
      );
      await pumpControls(
        tester,
        const VoiceState(state: VoiceSessionState.connected),
        session: session,
      );

      await tester.tap(find.byTooltip('Share a screen'));
      await tester.pumpAndSettle();

      expect(
        find.text('Everyone in the call will see it until you stop sharing.'),
        findsNothing,
        reason:
            'xdg-desktop-portal already asks; this sheet would be a second '
            'dialog for the same choice',
      );
      expect(session.screenShareCalls, hasLength(1));
      expect(session.screenShareCalls.single.sourceId, '1');
    },
  );

  testWidgets('the camera button is on the same row as hang up', (
    tester,
  ) async {
    final session = _InertSession();
    await pumpControls(
      tester,
      const VoiceState(state: VoiceSessionState.connected),
      session: session,
    );

    expect(find.byTooltip('Turn on camera'), findsOneWidget);
    expect(find.byTooltip('Leave call'), findsOneWidget);

    await tester.tap(find.byTooltip('Turn on camera'));
    await tester.pump();

    expect(session.setCameraCalls, [true]);
  });

  testWidgets('the switch-camera control only appears once the camera is on', (
    tester,
  ) async {
    await pumpControls(
      tester,
      const VoiceState(state: VoiceSessionState.connected),
    );
    expect(find.byTooltip('Switch camera'), findsNothing);

    await pumpControls(
      tester,
      const VoiceState(state: VoiceSessionState.connected, cameraEnabled: true),
    );
    expect(find.byTooltip('Switch camera'), findsOneWidget);
  });

  testWidgets('switching cameras flips directly on a platform with no picker', (
    tester,
  ) async {
    final session = _InertSession()..canFlipCamera = true;
    await pumpControls(
      tester,
      const VoiceState(state: VoiceSessionState.connected, cameraEnabled: true),
      session: session,
    );

    await tester.tap(find.byTooltip('Switch camera'));
    await tester.pumpAndSettle();

    expect(session.cameraSwitchCalls, ['flip']);
    // No sheet: the mobile flip needs nobody to choose anything.
    expect(find.text('Choose a camera'), findsNothing);
  });

  testWidgets('switching cameras opens a picker on a platform that needs one', (
    tester,
  ) async {
    final session = _InertSession()
      ..cameraNeedsSelection = true
      ..cameraDeviceList = const [
        CameraDevice(id: 'cam-1', label: 'Built-in webcam'),
        CameraDevice(id: 'cam-2', label: 'USB webcam'),
      ];
    await pumpControls(
      tester,
      const VoiceState(state: VoiceSessionState.connected, cameraEnabled: true),
      session: session,
    );

    await tester.tap(find.byTooltip('Switch camera'));
    // pump, not pumpAndSettle: the switch button's pending spinner never settles while the sheet awaits a choice.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('USB webcam'), findsOneWidget);
    await tester.tap(find.text('USB webcam'));
    await tester.pumpAndSettle();

    expect(session.cameraSwitchCalls, ['select:cam-2']);
  });
}
