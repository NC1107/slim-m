// SPDX-License-Identifier: Apache-2.0
#ifndef FLUTTER_LINUX_SECOND_INSTANCE_CHANNEL_H_
#define FLUTTER_LINUX_SECOND_INSTANCE_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

// The reverse of linux_tray_probe_channel.h: fired from native to Dart when
// my_application_activate() re-enters for a second launch; the Dart side is
// DesktopWindowShell.registerSecondInstanceHandler (desktop_window_shell.dart).
void linux_second_instance_channel_register(FlBinaryMessenger* messenger);
void linux_second_instance_channel_notify_focus();

#endif  // FLUTTER_LINUX_SECOND_INSTANCE_CHANNEL_H_
