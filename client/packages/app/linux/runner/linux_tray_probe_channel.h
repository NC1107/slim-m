// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#ifndef FLUTTER_LINUX_TRAY_PROBE_CHANNEL_H_
#define FLUTTER_LINUX_TRAY_PROBE_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

// The one method this channel answers, "isHostRegistered", queries
// org.kde.StatusNotifierWatcher's own IsStatusNotifierHostRegistered
// property over the session D-Bus bus; see docs/decisions/0012 for why this
// is a hand-written channel rather than a general-purpose Dart D-Bus
// package for one boolean. The Dart side is `linux_tray_probe.dart`.
// Absent, false, or an errored query all answer false: a stale "yes" would
// leave the window reachable by nothing at all once it hides.
void linux_tray_probe_channel_register(FlBinaryMessenger* messenger);

#endif  // FLUTTER_LINUX_TRAY_PROBE_CHANNEL_H_
