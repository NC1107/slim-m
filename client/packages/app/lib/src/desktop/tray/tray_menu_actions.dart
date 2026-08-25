// SPDX-License-Identifier: Apache-2.0
/// Which rows the tray/Dock menu shows, kept as one pure decision so the
/// content stays as short as decision 0012 asks for - "a tray menu is not a
/// settings screen" - without the ordering living only inside the widget
/// code that builds the real native menu.
library;

enum TrayMenuActionKind {
  showHide,
  presenceStatus,
  muteMicrophone,
  toggleDeafen,
  leaveCall,
  settings,
  quit,
}

/// Show/Hide, the status submenu, Settings and Quit always appear: the
/// window spends most of a session hidden, so setting a status and reaching
/// preferences are the only rows a chat app's tray is useful for without a
/// call live. Mute microphone, deafen and Leave call only surface while a
/// call is actually in progress, per the owner's own answer to decision
/// 0012's open question about menu contents.
List<TrayMenuActionKind> trayMenuActions({required bool inCall}) => [
  TrayMenuActionKind.showHide,
  TrayMenuActionKind.presenceStatus,
  if (inCall) ...[
    TrayMenuActionKind.muteMicrophone,
    TrayMenuActionKind.toggleDeafen,
    TrayMenuActionKind.leaveCall,
  ],
  TrayMenuActionKind.settings,
  TrayMenuActionKind.quit,
];
