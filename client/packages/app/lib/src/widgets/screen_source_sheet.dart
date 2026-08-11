// SPDX-License-Identifier: Apache-2.0
/// Choosing which screen to share, on the desktops that make the app ask.
/// Built on `device_choice_sheet.dart`, the shape `camera_source_sheet.dart`
/// shares.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';

import 'device_choice_sheet.dart';

/// Returns the chosen source, or null if the sheet was dismissed.
Future<ScreenShareSource?> showScreenSourceSheet(
  BuildContext context,
  List<ScreenShareSource> sources,
) {
  return showAppSheet<ScreenShareSource>(
    context,
    builder: (context) => DeviceChoiceSheet<ScreenShareSource>(
      title: 'Share a screen',
      caption: 'Everyone in the call will see it until you stop sharing.',
      icon: AppIcons.screenShare,
      items: sources,
      labelOf: (source) => source.name,
    ),
  );
}
