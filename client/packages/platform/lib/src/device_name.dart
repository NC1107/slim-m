// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The device name sent at sign-in, with a phone's model where the platform
/// gives one.
library;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

import 'host_platform.dart';

/// [deviceDisplayName], upgraded on a phone to the model the OS reports
/// ("iPhone", "Pixel 8"). Never throws: a plugin that cannot answer leaves the
/// fallback name.
Future<String> resolveDeviceName() async {
  if (kIsWeb) return deviceDisplayName;
  try {
    final plugin = DeviceInfoPlugin();
    final model = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => (await plugin.iosInfo).model,
      TargetPlatform.android => (await plugin.androidInfo).model,
      _ => null,
    };
    return composeDeviceName(
      defaultTargetPlatform,
      host: deviceHostName,
      model: model,
    );
  } catch (_) {
    return deviceDisplayName;
  }
}
