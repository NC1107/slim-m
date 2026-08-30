// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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
        CameraDevice(
          id: device.deviceId,
          label: device.label,
          groupId: device.groupId,
        ),
    ];
  }
}

/// Collapses [devices] down to one entry per physical camera.
///
/// Several UVC webcams - the owner's EMEET C960 among them - expose more
/// than one V4L2 capture node for a single physical device (an extra
/// metadata or secondary-stream node alongside the real one), and this
/// package's own `HardwareCameraDevices` passes every enumerated node
/// straight through with no such collapsing, which is what let the
/// switch-camera control believe a one-camera desktop had a choice to make.
///
/// [CameraDevice.groupId] is the strongest signal, when a platform actually
/// sets one: this app's own native desktop backend
/// (flutter_webrtc's `GetSources`) never populates it for video devices, so
/// on Linux/macOS/Windows today this always falls through to [label] - the
/// platform's own device name, which duplicate nodes of one physical webcam
/// do share (confirmed against flutter_webrtc's `GetDeviceName`, whose
/// `deviceUniqueIdUTF8` varies per node but whose name does not). A browser
/// that does report a real `groupId` gets to use it as the first choice,
/// since two distinct cameras could otherwise coincidentally share a label.
///
/// A blank label (a browser withholding it before permission is granted)
/// is never used to group: collapsing several distinctly-unlabelled devices
/// down to one would hide a real second camera, which is worse than not
/// deduplicating at all. Such a device is kept on its own [CameraDevice.id]
/// instead.
List<CameraDevice> dedupeCameraDevices(List<CameraDevice> devices) {
  final seenKeys = <String>{};
  return [
    for (final device in devices)
      if (seenKeys.add(_dedupeKey(device))) device,
  ];
}

String _dedupeKey(CameraDevice device) {
  final groupId = device.groupId;
  if (groupId != null && groupId.isNotEmpty) return 'group:$groupId';
  if (device.label.isNotEmpty) return 'label:${device.label}';
  return 'id:${device.id}';
}
