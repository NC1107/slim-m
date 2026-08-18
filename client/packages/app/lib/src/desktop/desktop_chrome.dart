// SPDX-License-Identifier: Apache-2.0
/// The one wrapper `main.dart`'s `appChromeBuilder` adds for the desktop
/// window shell: the frameless title bar, once it is actually active, and
/// the first-run tray notice banner, both mounted above the routed content
/// rather than deep inside `home_shell.dart`, so every screen gets them with
/// no change to any of them.
///
/// It carries its own [Material]. This sits in `MaterialApp`'s `builder`,
/// above the Navigator, so nothing here has a `Scaffold` - and without a
/// `Material` the title bar and banner inherit the fallback `DefaultTextStyle`,
/// which is a debug colour and an underline. That is the yellow underline the
/// title shipped with. The title bar's own tests wrap it in a `Scaffold` and
/// so never rendered it the way the real chrome does.
library;

import 'package:flutter/material.dart';

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

    // Transparent so each piece keeps its own surface; see the library doc for why a Material is here.
    return Material(
      type: MaterialType.transparency,
      child: Column(
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
      ),
    );
  }
}
