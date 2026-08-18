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
///
/// It also carries its own [Overlay]. The title bar's window menu opens through
/// an `OverlayPortal`, and being above the Navigator the title bar has no
/// `Overlay` ancestor of its own: the routed `child`'s Navigator has one, but
/// the title bar is that Navigator's sibling, not its descendant, so the menu
/// found no overlay and rendered as a stray band instead of a menu. This
/// overlay spans the whole window, so the menu opens below the title bar over
/// the content. Theme and media changes reach the content through it the way
/// any inherited value does, and the routed `child` a `MaterialApp` hands its
/// builder is a stable widget across rebuilds, so its single entry does not go
/// stale on navigation.
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

    // Transparent so each piece keeps its own surface; the library doc says why a Material and an Overlay are both here.
    return Material(
      type: MaterialType.transparency,
      child: Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (context) => Column(
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
          ),
        ],
      ),
    );
  }
}
