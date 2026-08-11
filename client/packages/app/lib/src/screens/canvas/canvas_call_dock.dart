// SPDX-License-Identifier: Apache-2.0
/// The one floating dock a voice call and the canvas share, so opening the
/// canvas during a call no longer costs the call its own controls.
///
/// Before this, a call's controls (`CallControls`) lived in a full-width bar
/// at the bottom of `VoiceScreen`, and the canvas's own controls
/// (`CanvasBar`, now `CanvasToolsRow`) lived in a full-width bar at the top
/// of `CanvasPane` - and opening the canvas swapped `VoiceScreen` out
/// entirely (`ConversationPane`'s stage ternary), taking the call's controls
/// with it. The owner reported this directly: "we should still have call
/// controls while in the canvas."
///
/// [CanvasCallDock] is the fix: one [FloatingDockCard], built with whichever
/// of [call] and [canvas] apply right now, so the exact same card renders a
/// call alone, a canvas alone, or both together. Nothing here decides
/// *whether* a call is active in this channel - `canvas_pane.dart` already
/// reads that off `voiceControllerProvider` for the presence layer, and
/// passes the same answer here.
///
/// **Primary versus secondary, decided rather than guessed.** The four call
/// controls (mic, camera, share, leave) are drawn first and never scroll -
/// they are the controls a hand reaches for without looking, and a call
/// nobody can mute or leave is the one failure this dock must never produce.
/// The canvas's five tools keep their own proven scroll-and-fade strip
/// (`CanvasToolsRow`) rather than folding behind a menu, the same "every
/// tool a same-level, one-tap button" reasoning decision 0004 already
/// settled; undo, the overflow menu and close are pinned outside that scroll
/// so they are never the thing clipped.
///
/// **Phone width stacks two rows in one card; a wide pane draws one.** Both
/// rows already fit their own width alone (four or five 44dp controls, or a
/// tool strip with its own internal scroll fallback), so combining them
/// needs no new overflow handling - only a width past which there is room to
/// sit side by side, taken from [kCompactWidth], the same touch/pointer line
/// `AppTouchTargets` already draws.
///
/// **The gaps either side of the divider shrank from [AppSpacing.s12] to
/// [AppSpacing.s8], the same compaction pass as `FloatingDockCard`'s own
/// inset and `voice_call_controls.dart`'s control size.** Nothing here
/// bounds a touch target - the row stays two rows below [kCompactWidth]
/// regardless, so a phone never sees this branch at all - so there was
/// nothing stopping the gap from tightening alongside everything else.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import '../voice_call_controls.dart';
import '../../providers/voice_controller.dart';
import '../../widgets/floating_dock_card.dart';
import 'canvas_tools_row.dart';

/// The call half of the dock: exactly what `CallControls` already needs.
class CallDockData {
  const CallDockData({required this.voice, required this.controller});

  final VoiceState voice;
  final VoiceController controller;
}

// CanvasHiddenTile lives in canvas_tools_row.dart, imported below - defining it there rather than here avoids a two-way import with CanvasOverflowMenu, its only other user.

/// The canvas half of the dock: exactly what [CanvasToolsRow] already needs.
class CanvasDockData {
  const CanvasDockData({
    required this.tool,
    required this.onToolChanged,
    required this.canUndo,
    required this.onUndo,
    required this.canManage,
    required this.objectCount,
    required this.onClear,
    required this.onPasteImage,
    required this.onRecenter,
    required this.selection,
    required this.onBringToFront,
    required this.onSendToBack,
    required this.onDeleteSelected,
    required this.activityLogOpen,
    required this.onToggleActivityLog,
    required this.shapeKind,
    required this.onShapeKindChanged,
    required this.onClose,
    required this.hasSelfBubble,
    required this.selfBubbleHidden,
    required this.onToggleSelfBubbleHidden,
    required this.hiddenTiles,
    required this.onShowTile,
  });

  final CanvasTool tool;
  final ValueChanged<CanvasTool> onToolChanged;
  final bool canUndo;
  final VoidCallback onUndo;
  final bool canManage;
  final ValueListenable<int> objectCount;
  final Future<void> Function() onClear;
  final VoidCallback onPasteImage;
  final VoidCallback onRecenter;
  final ValueListenable<String?> selection;
  final ValueChanged<String> onBringToFront;
  final ValueChanged<String> onSendToBack;
  final ValueChanged<String> onDeleteSelected;
  final bool activityLogOpen;
  final VoidCallback onToggleActivityLog;
  final CanvasShapeKind shapeKind;
  final ValueChanged<CanvasShapeKind> onShapeKindChanged;
  final VoidCallback onClose;

  /// Whether the caller is on this channel's call at all, and the overflow
  /// menu's own hide toggle for it - see `canvas_tools_row.dart`'s own doc
  /// on why the menu item is absent rather than merely disabled when this
  /// is false.
  final bool hasSelfBubble;
  final bool selfBubbleHidden;
  final VoidCallback onToggleSelfBubbleHidden;

  /// Every remote camera or screen-share tile hidden on this viewer's own
  /// canvas right now, and the recovery action for each - a hide must stay
  /// reversible without leaving the call.
  final List<CanvasHiddenTile> hiddenTiles;
  final ValueChanged<String> onShowTile;
}

/// [call] whenever this device is actually connected to a call in
/// [channelId], null otherwise - the one question `canvas_pane.dart` has to
/// ask before it can hand this dock a call section at all. Read fresh on
/// every build rather than cached, since a call joined or left while the
/// canvas stays open must show up here on the very next frame.
CallDockData? callDockDataFor(
  VoiceState voice,
  VoiceController controller,
  String channelId,
) {
  if (voice.channelId != channelId) return null;
  if (voice.state != VoiceSessionState.connected) return null;
  return CallDockData(voice: voice, controller: controller);
}

class CanvasCallDock extends StatelessWidget {
  const CanvasCallDock({super.key, this.call, this.canvas})
    : assert(
        call != null || canvas != null,
        'a dock with neither a call nor a canvas has nothing to show',
      );

  final CallDockData? call;
  final CanvasDockData? canvas;

  @override
  Widget build(BuildContext context) {
    final call = this.call;
    final canvas = this.canvas;
    if (call == null) {
      return FloatingDockCard(rows: [_ToolsRow(canvas: canvas!)]);
    }
    final callRow = CallControls(
      controller: call.controller,
      voice: call.voice,
    );
    if (canvas == null) {
      return FloatingDockCard(rows: [callRow]);
    }
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final oneRow = constraints.maxWidth >= kCompactWidth;
        return FloatingDockCard(
          rows: oneRow
              ? [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      callRow,
                      const SizedBox(width: AppSpacing.s8),
                      SizedBox(
                        height: AppSpacing.s24,
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: tokens.borderSubtle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.s8),
                      Flexible(child: _ToolsRow(canvas: canvas)),
                    ],
                  ),
                ]
              : [Center(child: callRow), _ToolsRow(canvas: canvas)],
        );
      },
    );
  }
}

class _ToolsRow extends StatelessWidget {
  const _ToolsRow({required this.canvas});

  final CanvasDockData canvas;

  @override
  Widget build(BuildContext context) => CanvasToolsRow(
    tool: canvas.tool,
    onToolChanged: canvas.onToolChanged,
    canUndo: canvas.canUndo,
    onUndo: canvas.onUndo,
    canManage: canvas.canManage,
    objectCount: canvas.objectCount,
    onClear: canvas.onClear,
    onPasteImage: canvas.onPasteImage,
    onRecenter: canvas.onRecenter,
    selection: canvas.selection,
    onBringToFront: canvas.onBringToFront,
    onSendToBack: canvas.onSendToBack,
    onDeleteSelected: canvas.onDeleteSelected,
    activityLogOpen: canvas.activityLogOpen,
    onToggleActivityLog: canvas.onToggleActivityLog,
    shapeKind: canvas.shapeKind,
    onShapeKindChanged: canvas.onShapeKindChanged,
    onClose: canvas.onClose,
    hasSelfBubble: canvas.hasSelfBubble,
    selfBubbleHidden: canvas.selfBubbleHidden,
    onToggleSelfBubbleHidden: canvas.onToggleSelfBubbleHidden,
    hiddenTiles: canvas.hiddenTiles,
    onShowTile: canvas.onShowTile,
    showTools: !canvas.activityLogOpen,
  );
}
