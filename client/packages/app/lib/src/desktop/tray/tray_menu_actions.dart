// SPDX-License-Identifier: Apache-2.0
/// Which rows the tray/Dock menu shows, kept as one pure decision so the
/// content stays as short as decision 0012 asks for - "a tray menu is not a
/// settings screen" - without the ordering living only inside the widget
/// code that builds the real native menu.
library;

enum TrayMenuActionKind { showHide, muteMicrophone, leaveCall, quit }

/// Show/Hide and Quit always appear; Mute microphone and Leave call only
/// while a call is actually live, per the owner's own answer to decision
/// 0012's open question about menu contents.
List<TrayMenuActionKind> trayMenuActions({required bool inCall}) => [
  TrayMenuActionKind.showHide,
  if (inCall) ...[
    TrayMenuActionKind.muteMicrophone,
    TrayMenuActionKind.leaveCall,
  ],
  TrayMenuActionKind.quit,
];
