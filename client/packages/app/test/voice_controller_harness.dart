// SPDX-License-Identifier: Apache-2.0
/// Shared fixtures for the two suites that drive a [VoiceController]: the
/// controller's own behaviour, and the iOS broadcast handoff.
///
/// Not a `_test.dart` file, so `flutter test` does not try to run it. Both
/// suites need the same hand-driven [VoiceSession], the same token endpoint
/// and the same provider wiring around them.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart';
import 'package:slimm_app/src/diagnostics/debug_log.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/voice_controller.dart';
import 'package:slimm_platform/platform.dart';
import 'package:slimm_rtc/rtc.dart';

const tokens = TokenPair(
  userId: 'user-1',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// A [VoiceSession] the test drives by hand.
///
/// Implemented rather than subclassed so that adding a method to the real
/// session is a compile error here, not a silently untested path.
class FakeSession implements VoiceSession {
  @override
  bool get supportsParticipantVolume => true;

  final Map<String, double> _volumes = {};

  @override
  double volumeFor(String identity) => _volumes[identity] ?? 1.0;

  @override
  Future<void> setVolumeFor(String identity, double volume) async {
    _volumes[identity] = volume.clamp(0.0, 2.0);
  }

  FakeSession({
    this.joinOutcome = VoiceSessionState.connected,
    this.microphoneGranted = true,
    this.cameraGranted = true,
    this.screenShareOutcome = ScreenShareOutcome.started,
    this.deafenGranted = true,
    this.needsSource = false,
    this.sources = const [],
    this.sourcePickerUseful = true,
    this.canFlipCamera = false,
    this.cameraNeedsSelection = false,
    this.cameraDeviceList = const [],
  });

  final VoiceSessionState joinOutcome;
  final bool microphoneGranted;
  final bool cameraGranted;

  /// What a request to start sharing reports back. Every branch the
  /// controller has to tell apart is one of these.
  final ScreenShareOutcome screenShareOutcome;
  final bool deafenGranted;

  /// Whether this platform makes a share name a screen first.
  final bool needsSource;
  final List<ScreenShareSource> sources;

  /// Whether several enumerated sources are worth their own picker; see
  /// [DesktopSources.sourcePickerUseful].
  final bool sourcePickerUseful;

  @override
  final bool canFlipCamera;

  @override
  final bool cameraNeedsSelection;

  /// What [cameraDevices] answers with.
  final List<CameraDevice> cameraDeviceList;

  /// What the controller actually passed through, so a test can assert the
  /// chosen camera reached the session.
  CameraDevice? lastSelectedCamera;
  int flipCameraCalls = 0;
  bool? askedForCameraOnToggle;

  /// What the controller actually passed through, so a test can assert the
  /// chosen screen reached the session rather than being dropped.
  String? lastSourceId;
  int sourceListings = 0;

  final _states = StreamController<VoiceSessionState>.broadcast();
  final _participants = StreamController<List<VoiceParticipant>>.broadcast();

  VoiceSessionState _state = VoiceSessionState.idle;
  bool? askedForMicrophoneOnJoin;
  bool? askedForCameraOnJoin;
  int leaveCalls = 0;

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

  Object? _lastError;

  @override
  Object? get lastError =>
      _lastError ??
      (_state == VoiceSessionState.failed ? 'the SFU refused' : null);

  @override
  VoiceDisconnect? lastDisconnect;

  @override
  bool get screenShareNeedsSource => needsSource;

  @override
  bool get screenShareSourcePickerUseful => sourcePickerUseful;

  @override
  Future<List<ScreenShareSource>> screenShareSources() async {
    sourceListings++;
    return sources;
  }

  /// Keyed so a widget test can assert the share surface mounted for the
  /// right participant without a real room behind it.
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

  @override
  Future<List<CameraDevice>> cameraDevices() async => cameraDeviceList;

  @override
  Future<bool> flipCamera() async {
    flipCameraCalls++;
    return cameraGranted;
  }

  @override
  Future<bool> selectCameraDevice(CameraDevice device) async {
    lastSelectedCamera = device;
    return cameraGranted;
  }

  /// Drives a drop the SFU decided on, the way a real room event would.
  void dropWith(VoiceDisconnect reason) {
    lastDisconnect = reason;
    _state = VoiceSessionState.failed;
    _states.add(_state);
  }

  /// Pushes any other session-state transition through the same stream
  /// `join`'s own outcome never emits on, since nothing here drives a real
  /// `Room`'s events.
  void emitState(VoiceSessionState next) {
    _state = next;
    _states.add(next);
  }

  @override
  Future<void> join({
    required String url,
    required String token,
    bool microphoneEnabled = true,
    bool cameraEnabled = false,
  }) async {
    askedForMicrophoneOnJoin = microphoneEnabled;
    askedForCameraOnJoin = cameraEnabled;
    _state = joinOutcome;
  }

  @override
  Future<void> leave() async {
    leaveCalls++;
    _state = VoiceSessionState.idle;
    // The real session emits this transition too, and a fake that did not was untested here.
    _states.add(_state);
  }

  @override
  Future<bool> setMicrophoneEnabled(bool enabled) async => microphoneGranted;

  /// Records a cause on refusal, `setScreenShareEnabled`'s own reasoning
  /// below: a fake that drops it cannot catch a controller that does too.
  @override
  Future<bool> setCameraEnabled(bool enabled) async {
    askedForCameraOnToggle = enabled;
    if (!cameraGranted) _lastError = 'no camera device found';
    return cameraGranted;
  }

  @override
  Future<ScreenShareOutcome> setScreenShareEnabled(
    bool enabled, {
    ScreenShareQuality quality = ScreenShareQuality.balanced,
    String? sourceId,
  }) async {
    lastSourceId = sourceId;
    if (!enabled) return ScreenShareOutcome.stopped;
    // The real session records why before reporting failure; a fake that does
    // not cannot catch a controller that drops the cause.
    if (screenShareOutcome == ScreenShareOutcome.failed) {
      _lastError = 'source not found!';
    }
    return screenShareOutcome;
  }

  @override
  Future<bool> setDeafened(bool value) async {
    if (!deafenGranted) return false;
    deafened = value;
    return true;
  }

  @override
  Future<void> dispose() async {
    await _states.close();
    await _participants.close();
  }

  void emitParticipants(List<VoiceParticipant> p) => _participants.add(p);
}

/// Answers the token and heartbeat endpoints however the test asks.
///
/// [sfuUrl] defaults to a wss address, the only shape the server's own
/// config validation and most tests need; the plain-ws suite overrides it.
/// [onRequest], when given, is called with every request this client
/// answers, so a test can count or inspect heartbeat calls without a second
/// mock layered on top. The whole request, not just the url: a POST
/// heartbeat and the DELETE that forgets one on a clean leave share a path,
/// and only the method tells them apart.
http.Client voiceApi({
  int status = 200,
  bool canPublish = true,
  String sfuUrl = 'wss://sfu.example.com',
  void Function(http.Request request)? onRequest,
}) {
  return MockClient((request) async {
    onRequest?.call(request);
    if (request.url.path.endsWith('/voice/heartbeat')) {
      return http.Response('', 204);
    }
    if (!request.url.path.endsWith('/voice/token')) {
      return http.Response('{}', 404);
    }
    if (status != 200) {
      return http.Response(
        jsonEncode({
          'error': {'code': 'nope', 'message': 'refused'},
        }),
        status,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response(
      jsonEncode({
        'url': sfuUrl,
        'room': 'channel-1',
        'token': 'jwt',
        'expires_at': 0,
        'can_publish': canPublish,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  });
}

/// A [VoiceController] pinned to [fixed], for a test that renders against a
/// known [VoiceState] without driving a real join through it. `state` is
/// only settable from within a [VoiceController] subclass, never from
/// outside one, which is why this exists rather than a plain field assign.
class FixedVoiceController extends VoiceController {
  FixedVoiceController(super.ref, VoiceState fixed)
    : super(session: FakeSession()) {
    state = fixed;
  }
}

/// Owns the container so a suite can tear it down in one place.
class VoiceHarness {
  ProviderContainer? _container;

  /// For a widget test to wrap in `UncontrolledProviderScope`; only valid
  /// after [controllerWith] has built one.
  ProviderContainer get container => _container!;

  void dispose() => _container?.dispose();

  /// What the controller recorded for the user to read back in settings.
  List<DiagnosticEvent> log(VoiceController _) =>
      _container!.read(debugLogProvider);

  /// The controller as the app builds it, with only the network and the SFU
  /// swapped: a real session, a real [SlimmApi], and the same provider wiring.
  VoiceController controllerWith(
    FakeSession session,
    http.Client client, {
    Duration broadcastStartTimeout = const Duration(seconds: 30),
    Duration voiceHeartbeatInterval = const Duration(seconds: 15),
    CallLifecycleChannel? callLifecycle,
  }) {
    final container = ProviderContainer(
      overrides: [
        keyStoreProvider.overrideWithValue(InMemoryKeyStore()),
        sessionProvider.overrideWithValue(SessionStore(tokens: tokens)),
        apiProvider.overrideWith((ref) {
          final api = SlimmApi(
            baseUrl: Uri.parse('http://localhost:8080'),
            session: ref.watch(sessionProvider),
            httpClient: client,
          );
          ref.onDispose(api.close);
          return api;
        }),
        voiceControllerProvider.overrideWith(
          (ref) => VoiceController(
            ref,
            session: session,
            broadcastStartTimeout: broadcastStartTimeout,
            voiceHeartbeatInterval: voiceHeartbeatInterval,
            callLifecycle: callLifecycle,
          ),
        ),
      ],
    );
    _container = container;
    return container.read(voiceControllerProvider.notifier);
  }
}
