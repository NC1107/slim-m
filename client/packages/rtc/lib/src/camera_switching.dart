// SPDX-License-Identifier: Apache-2.0
/// Flipping or picking a camera, split out of `voice_session.dart` to make
/// room there under this repo's file budget.
///
/// Mirrors `screen_share_control.dart`'s own shape: the room is handed in per
/// call rather than held here, so this stays a plain, test-friendly class
/// with no LiveKit connection of its own to fake.
library;

import 'package:flutter_webrtc/flutter_webrtc.dart' as webrtc;
import 'package:livekit_client/livekit_client.dart' as lk;

import 'camera_devices.dart';
import 'camera_failure.dart';
import 'voice_models.dart';

/// What came of a camera enable/disable attempt. [reason] is only ever set
/// alongside a failed *enable* (see [CameraSwitching.setEnabled]), since
/// "no camera detected" has no sensible reading for a camera that was
/// already on and failed to turn off.
class CameraToggleResult {
  const CameraToggleResult.ok()
      : cause = null,
        reason = null;

  const CameraToggleResult.failed(this.cause, this.reason);

  bool get ok => cause == null;

  final Object? cause;
  final CameraFailureReason? reason;

  /// What [VoiceSession] should store as `lastError`: [cause] wrapped in a
  /// [CameraFailure] when [reason] is known, so that one getter keeps
  /// answering every failure while still letting a caller ask this apart.
  Object? get error =>
      reason == null || cause == null ? cause : CameraFailure(cause!, reason!);
}

class CameraSwitching {
  const CameraSwitching(this._devices);

  final CameraDevices _devices;

  /// Whether flipping between a front and back camera needs no chosen
  /// device: mobile only, where the OS - not a list - decides which camera
  /// answers "front" or "back". See [needsSelection] for the opposite case.
  bool get canFlip => lk.lkPlatformIsMobile();

  /// Whether picking a camera needs one named first, the same reason
  /// `screenShareNeedsSource` exists: several desktop webcams are otherwise
  /// indistinguishable to whatever camera the OS opens by default.
  bool get needsSelection => !lk.lkPlatformIsMobile();

  Future<List<CameraDevice>> devices() => _devices.list();

  /// Enables or disables [local]'s camera, classifying the failure when
  /// enabling does not work.
  ///
  /// A disable failure is reported with no [CameraFailureReason.noCameraDetected]
  /// framing: the camera was already on, so a device plainly exists, and the
  /// caller (`VoiceSession._trySetCamera`) does not ask for one in that case.
  /// [_devices] is only consulted here, on failure, rather than on every
  /// attempt: it is an extra round trip that only the error message needs.
  Future<CameraToggleResult> setEnabled(
    lk.LocalParticipant? local,
    bool enabled,
  ) async {
    if (local == null) return const CameraToggleResult.ok();
    try {
      await local.setCameraEnabled(enabled);
      return const CameraToggleResult.ok();
    } catch (e) {
      if (!enabled) return CameraToggleResult.failed(e, null);
      bool? hasDevice;
      try {
        hasDevice = (await _devices.list()).isNotEmpty;
      } catch (_) {
        hasDevice = null;
      }
      return CameraToggleResult.failed(
        e,
        classifyCameraFailure(e, hasDevice: hasDevice),
      );
    }
  }

  /// Flips [local]'s published camera between front and back. Native
  /// `Helper.switchCamera` with no device id is the platform's own flip: it
  /// asks the OS which camera answers next rather than naming one.
  Future<bool> flip(lk.LocalParticipant? local) async {
    if (local == null) return false;
    for (final pub in local.videoTrackPublications) {
      if (pub.source != lk.TrackSource.camera) continue;
      final track = pub.track;
      if (track == null) continue;
      return webrtc.Helper.switchCamera(track.mediaStreamTrack);
    }
    return false;
  }

  /// Switches [room]'s published camera to [device], desktop's answer to
  /// [flip] where more than one webcam can exist. Also updates the room's
  /// default capture device, so a camera enabled again later opens the one
  /// just chosen rather than reverting to the platform default.
  Future<void> select(lk.Room room, CameraDevice device) =>
      room.setVideoInputDevice(
          lk.MediaDevice(device.id, device.label, 'videoinput', null));
}
