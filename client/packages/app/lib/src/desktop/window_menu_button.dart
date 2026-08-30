// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The one guaranteed quit path, reachable with no tray host at all.
///
/// `close_behavior.dart`'s [CloseAction.minimizeToTaskbar] exists so a
/// Linux desktop with no `org.kde.StatusNotifierWatcher` never gets a
/// window hidden with nothing to bring it back - but the only place a real
/// quit ever lived was the tray menu's own "Quit slim-m" item, and that
/// menu does not exist without a tray host either. The X button and Alt+F4
/// both resolve to minimise on such a desktop, forever, with no affordance
/// anywhere in the running app that actually ends the process.
///
/// This button is unconditional, mounted regardless of whether a tray is
/// reachable right now: probing live and hiding the button when a tray is
/// found would only move the trap rather than close it, since the probe
/// answers differently across the session (decision 0012's own note that a
/// tray host can appear or disappear mid-session) and a control that
/// vanishes out from under a keyboard user mid-navigation is its own bug.
/// A second, always-reachable way to reach the same "Quit slim-m" the tray
/// menu already offers costs nothing on a desktop that does have a tray.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../widgets/context_menu_focus.dart';
import 'desktop_window_port.dart';

class WindowMenuButton extends StatefulWidget {
  const WindowMenuButton({super.key, required this.port});

  final DesktopWindowPort port;

  @override
  State<WindowMenuButton> createState() => _WindowMenuButtonState();
}

class _WindowMenuButtonState extends State<WindowMenuButton> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        // Positioned so the follower sizes to its content, not the screen.
        overlayChildBuilder: (context) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            // A right-edge trigger opens leftward, or it runs off the window.
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 4),
            child: TapRegion(
              onTapOutside: (_) => _controller.hide(),
              // Escape closes it and Tab reaches every item once open.
              child: ContextMenuKeyboardScope(
                onDismiss: _controller.hide,
                child: AppMenu(
                  width: 160,
                  children: [
                    AppMenuItem(
                      label: 'Quit slim-m',
                      leading: AppIcons.windowQuit,
                      onTap: () {
                        _controller.hide();
                        widget.port.destroy();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        child: AppIconButton(
          icon: AppIcons.moreVertical,
          semanticLabel: 'Window menu',
          size: AppIconButtonSize.sm,
          onPressed: _controller.toggle,
        ),
      ),
    );
  }
}
