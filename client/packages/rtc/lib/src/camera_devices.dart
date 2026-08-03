// SPDX-License-Identifier: Apache-2.0
/// Enumerating the cameras a desktop offers, for the picker several webcams
/// makes necessary.
///
/// Mobile never calls this: the OS owns which camera answers "the camera",
/// and flipping it is `Helper.switchCamera`'s job (see `VoiceSession.flipCamera`),
/// not a list to choose from.
library;

import 'package:livekit_client/livekit_client.dart' as lk;

import 'voice_models.dart';

/// The seam. The default implementation asks the platform's own device
/// list; a test supplies its own.
abstract class CameraDevices {
  Future<List<CameraDevice>> list();
}

class HardwareCameraDevices implements CameraDevices {
  const HardwareCameraDevices();

  @override
  Future<List<CameraDevice>> list() async {
    final devices = await lk.Hardware.instance.videoInputs();
    return [
      for (final device in devices)
        CameraDevice(id: device.deviceId, label: device.label),
    ];
  }
}
