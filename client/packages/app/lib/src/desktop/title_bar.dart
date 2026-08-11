// SPDX-License-Identifier: Apache-2.0
/// The custom title bar, decision 0012: one widget, branched once at the
/// place window-control layout actually differs per platform, rather than
/// three separate widgets duplicating the shared drag region and height.
///
/// Ships for Linux only in this change - the only platform with a runner
/// scaffolded at all (`docs/os_backlog/windows_backlog.md`,
/// `docs/os_backlog/macos_backlog.md`) - with the macOS traffic-lights
/// branch and the Windows controls-right branch left as the seam to fill
/// once each platform is actually built, not as dead code nobody can prove
/// works. [DesktopWindowShell] only ever hides the native frame on Linux, so
/// this widget is unreachable on the other two branches in this build.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import 'close_behavior.dart';
import 'desktop_window_port.dart';
import 'window_menu_button.dart';

/// The proposed height, a step on the 4dp grid and a real reduction from a
/// native GNOME header bar's roughly 46-48dp - not yet measured against the
/// owner's own GTK theme; see decision 0012's own "what is unsure" list.
const double titleBarHeight = AppSpacing.s40;

/// macOS's own traffic-light inset, left as a named constant rather than a
/// literal so the seam is easy to find once macOS is actually scaffolded and
/// this number can be checked against a real window.
const double _macOSTrafficLightInset = 78;

class TitleBar extends StatelessWidget {
  const TitleBar({
    super.key,
    required this.port,
    required this.platform,
    required this.onRequestClose,
    this.title = 'slim-m',
  });

  final DesktopWindowPort port;
  final DesktopPlatform platform;

  /// Routes through [DesktopWindowController.requestClose] rather than
  /// [DesktopWindowPort.hide] directly - the close button drawn here has no
  /// native close/delete-event of its own to trigger the tray-availability
  /// fallback, so it has to ask for the same decision explicitly.
  final Future<void> Function() onRequestClose;
  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>() ?? AppTokens.dark;
    final isMac = platform == DesktopPlatform.macOS;

    return SizedBox(
      height: titleBarHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceBase,
          border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
        ),
        child: Row(
          children: [
            if (isMac) const SizedBox(width: _macOSTrafficLightInset),
            const SizedBox(width: AppSpacing.s12),
            AppBrandMark(size: AppSizes.icon20, color: tokens.accent),
            const SizedBox(width: AppSpacing.s8),
            Text(
              title,
              style: AppText.ui.copyWith(color: tokens.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
            Expanded(child: _DragRegion(port: port)),
            if (!isMac)
              _WindowControls(port: port, onRequestClose: onRequestClose),
          ],
        ),
      ),
    );
  }
}

/// The bar's own empty middle: dragging moves the window, and a double-tap
/// toggles maximized the way a native title bar already does for free -
/// `window_manager` gives neither back once the frame is gone.
class _DragRegion extends StatelessWidget {
  const _DragRegion({required this.port});

  final DesktopWindowPort port;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onPanStart: (_) => port.startDragging(),
    onDoubleTap: _toggleMaximize,
    child: const SizedBox.expand(),
  );

  Future<void> _toggleMaximize() async {
    if (await port.isMaximized()) {
      await port.unmaximize();
    } else {
      await port.maximize();
    }
  }
}

class _WindowControls extends StatefulWidget {
  const _WindowControls({required this.port, required this.onRequestClose});

  final DesktopWindowPort port;
  final Future<void> Function() onRequestClose;

  @override
  State<_WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<_WindowControls> {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    widget.port.isMaximized().then((value) {
      if (mounted) setState(() => _maximized = value);
    });
  }

  Future<void> _maximizeOrRestore() async {
    if (await widget.port.isMaximized()) {
      await widget.port.unmaximize();
    } else {
      await widget.port.maximize();
    }
    if (mounted) setState(() => _maximized = !_maximized);
  }

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      WindowMenuButton(port: widget.port),
      const SizedBox(width: AppSpacing.s4),
      AppIconButton(
        icon: AppIcons.windowMinimize,
        semanticLabel: 'Minimize',
        size: AppIconButtonSize.sm,
        onPressed: widget.port.minimize,
      ),
      AppIconButton(
        icon: _maximized ? AppIcons.windowRestore : AppIcons.windowMaximize,
        semanticLabel: _maximized ? 'Restore' : 'Maximize',
        size: AppIconButtonSize.sm,
        onPressed: _maximizeOrRestore,
      ),
      AppIconButton(
        icon: AppIcons.windowClose,
        semanticLabel: 'Close',
        size: AppIconButtonSize.sm,
        variant: AppIconButtonVariant.danger,
        onPressed: widget.onRequestClose,
      ),
      const SizedBox(width: AppSpacing.s4),
    ],
  );
}
