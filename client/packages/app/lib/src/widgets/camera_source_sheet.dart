// SPDX-License-Identifier: Apache-2.0
/// Choosing which camera to publish, on the desktops (and browsers) where
/// more than one may exist. Mirrors `screen_source_sheet.dart` exactly.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

/// Returns the chosen device, or null if the sheet was dismissed.
Future<CameraDevice?> showCameraDeviceSheet(
  BuildContext context,
  List<CameraDevice> devices,
) {
  return showAppSheet<CameraDevice>(
    context,
    builder: (context) => _CameraDeviceSheet(devices: devices),
  );
}

class _CameraDeviceSheet extends StatelessWidget {
  const _CameraDeviceSheet({required this.devices});

  final List<CameraDevice> devices;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              0,
              AppSpacing.s16,
              AppSpacing.s12,
            ),
            child: Text('Choose a camera', style: AppText.heading),
          ),
          for (final device in devices)
            ListTile(
              leading: const Icon(AppIcons.camera),
              title: Text(device.label),
              onTap: () => Navigator.of(context).pop(device),
            ),
          const SizedBox(height: AppSpacing.s8),
        ],
      ),
    );
  }
}
