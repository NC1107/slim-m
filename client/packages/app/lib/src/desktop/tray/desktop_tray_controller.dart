// SPDX-License-Identifier: Apache-2.0
/// Builds and rebuilds the tray icon's context menu, and routes its three
/// kinds of item to the window port or the running call.
///
/// This is the one file in the desktop shell that talks to `tray_manager`'s
/// real singleton directly rather than through a seam: the icon and menu are
/// themselves a native singleton resource the same way `window_manager`'s
/// window is, and `tray_menu_actions.dart` already carries the one piece of
/// this that is worth testing headlessly - which rows appear at all.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:tray_manager/tray_manager.dart';

import '../../providers/voice_controller.dart';
import '../desktop_window_port.dart';
import 'tray_menu_actions.dart';

const trayIconAssetPath = 'assets/icons/tray_icon.png';

class DesktopTrayController {
  DesktopTrayController({required this.port, required this.container});

  final DesktopWindowPort port;
  final ProviderContainer container;

  ProviderSubscription<VoiceState>? _voiceSubscription;

  Future<void> start() async {
    await TrayManager.instance.setIcon(trayIconAssetPath);
    await TrayManager.instance.setToolTip('slim-m');
    await _rebuildMenu(container.read(voiceControllerProvider));
    _voiceSubscription = container.listen<VoiceState>(voiceControllerProvider, (
      previous,
      next,
    ) {
      if (previous?.state == next.state &&
          previous?.microphoneEnabled == next.microphoneEnabled) {
        return;
      }
      _rebuildMenu(next);
    });
  }

  void dispose() {
    _voiceSubscription?.close();
  }

  Future<void> _rebuildMenu(VoiceState voiceState) async {
    final inCall = voiceState.state == VoiceSessionState.connected;
    final items = trayMenuActions(
      inCall: inCall,
    ).map((kind) => _itemFor(kind, voiceState)).toList(growable: false);
    await TrayManager.instance.setContextMenu(Menu(items: items));
  }

  MenuItem _itemFor(TrayMenuActionKind kind, VoiceState voiceState) =>
      switch (kind) {
        TrayMenuActionKind.showHide => MenuItem(
          label: 'Show/Hide slim-m',
          onClick: (_) => _toggleVisibility(),
        ),
        TrayMenuActionKind.muteMicrophone => MenuItem(
          label: voiceState.microphoneEnabled
              ? 'Mute microphone'
              : 'Unmute microphone',
          onClick: (_) => container
              .read(voiceControllerProvider.notifier)
              .toggleMicrophone(),
        ),
        TrayMenuActionKind.leaveCall => MenuItem(
          label: 'Leave call',
          onClick: (_) =>
              container.read(voiceControllerProvider.notifier).leave(),
        ),
        TrayMenuActionKind.quit => MenuItem(
          label: 'Quit slim-m',
          onClick: (_) => port.destroy(),
        ),
      };

  Future<void> _toggleVisibility() async {
    if (await port.isVisible()) {
      await port.hide();
    } else {
      await port.show();
    }
  }
}
