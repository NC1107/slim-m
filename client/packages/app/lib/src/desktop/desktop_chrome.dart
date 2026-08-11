// SPDX-License-Identifier: Apache-2.0
/// The one wrapper `main.dart`'s `appChromeBuilder` adds for the desktop
/// window shell: the frameless title bar, once it is actually active, and
/// the first-run tray notice banner, both mounted above the routed content
/// rather than deep inside `home_shell.dart`, so every screen gets them with
/// no change to any of them.
library;

import 'package:flutter/widgets.dart';

import 'close_behavior.dart';
import 'desktop_window_shell.dart';
import 'first_run_tray_notice_banner.dart';
import 'title_bar.dart';

class DesktopChrome extends StatelessWidget {
  const DesktopChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!DesktopWindowShell.active) return child;

    return Column(
      children: [
        // frameless is only ever set true on the Linux branch below.
        if (DesktopWindowShell.frameless)
          TitleBar(
            port: DesktopWindowShell.port,
            platform: DesktopPlatform.linux,
            onRequestClose: DesktopWindowShell.requestClose,
          ),
        const FirstRunTrayNoticeBanner(),
        Expanded(child: child),
      ],
    );
  }
}
