// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// What to tell somebody whose camera would not turn on.
///
/// Split out of `voice_controller.dart`, which `voice_state.dart`'s own doc
/// comment already records these diagnostics as having pushed past this
/// repo's 500-line hard ceiling once. A pure mapping from a refusal to a
/// sentence is the seam with least to do with the rest of that file: it
/// touches no controller state, no session and no provider, so it moves
/// whole rather than leaving a stub behind.
library;

import 'package:slimm_rtc/rtc.dart';

/// [wantOn] is only ever asking "tried to turn on": a camera failing to turn
/// *off* was plainly already open, so [CameraFailureReason] has nothing
/// useful to say there and the raw cause is kept as before.
String cameraFailureMessage(bool wantOn, Object? cause) {
  final reason = wantOn && cause is CameraFailure ? cause.reason : null;
  return switch (reason) {
    CameraFailureReason.noCameraDetected =>
      'No camera detected. Check that one is connected.',
    CameraFailureReason.permissionDenied =>
      'Camera access was denied. Check your camera permission for this app.',
    CameraFailureReason.cameraUnavailable =>
      'The camera could not be opened. It may be in use by another app.',
    CameraFailureReason.unknown || null =>
      'Could not turn the camera ${wantOn ? 'on' : 'off'}. ${cause ?? ''}'
          .trim(),
  };
}
