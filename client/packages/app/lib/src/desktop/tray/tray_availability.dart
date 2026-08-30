// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Whether a tray is reachable right now, combining the platform (macOS's
/// Dock and Windows' notification area are both unconditional) with the
/// Linux-only runtime probe, decision 0012's own split.
library;

import '../close_behavior.dart';
import 'linux_tray_probe.dart';

/// [platform] and [probe] captured once; the returned closure re-checks the
/// probe on every call, since [DesktopWindowController.trayAvailable] must
/// query live rather than cache - a tray host can appear or disappear
/// mid-session (an extension toggled, a panel restarted).
Future<bool> Function() trayAvailabilityCheck({
  required DesktopPlatform platform,
  required LinuxTrayProbe probe,
}) => () async {
  if (platform != DesktopPlatform.linux) return true;
  return probe.isHostRegistered();
};
