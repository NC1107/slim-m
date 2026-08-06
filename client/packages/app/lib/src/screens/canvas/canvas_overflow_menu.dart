// SPDX-License-Identifier: Apache-2.0
/// The canvas bar's overflow: "Paste image" and "Show/Hide activity log" are
/// always present, since placing an image needs only the USE_CANVAS bit
/// drawing already does and the activity log is an accessibility fallback
/// nobody should need a permission for; "Bring to front"/"Send to back"/
/// "Delete" appear only while something is selected and "Clear canvas"
/// appears only for MANAGE_CANVAS. The four shape-kind rows appear only
/// while the Shape tool is active - not on the fixed-height bar itself,
/// which has no room for a fourth control per tool, and this menu already
/// has room to grow.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import '../../widgets/confirm_dialog.dart';
import '../../widgets/context_menu_focus.dart';

/// The bar's own overflow trigger and the confirm dialog behind Clear.
///
/// Clear stays behind a menu item rather than a bare button even when it is
/// the only reason a manager opens this: the extra tap is deliberate
/// friction on the one control here that removes more than the caller's own
/// selection, matching `manage_channel_sheet.dart`'s own danger-zone
/// separation. Delete needs no such friction: it takes exactly the one
/// object already selected, the same immediacy the eraser tool already
/// gives a stroke.
class CanvasOverflowMenu extends StatefulWidget {
  const CanvasOverflowMenu({
    super.key,
    required this.onPasteImage,
    required this.canManage,
    required this.objectCount,
    required this.onClear,
    required this.selection,
    required this.onBringToFront,
    required this.onSendToBack,
    required this.onDeleteSelected,
    required this.activityLogOpen,
    required this.onToggleActivityLog,
    required this.tool,
    required this.shapeKind,
    required this.onShapeKindChanged,
  });

  final VoidCallback onPasteImage;
  final bool canManage;
  final ValueListenable<int> objectCount;
  final Future<void> Function() onClear;

  /// The bar's own current tool, read only to decide whether the shape-kind
  /// rows below apply - this menu never changes it.
  final CanvasTool tool;
  final CanvasShapeKind shapeKind;
  final ValueChanged<CanvasShapeKind> onShapeKindChanged;

  /// The one object currently selected for a resize or reorder, or null.
  /// "Bring to front"/"Send to back" appear only while this holds an id,
  /// the same "no button that would just do nothing" choice
  /// `AppSegmentedOption.disabled` already makes elsewhere on this canvas.
  final ValueListenable<String?> selection;
  final ValueChanged<String> onBringToFront;
  final ValueChanged<String> onSendToBack;

  /// Removes the current selection outright - an image, note, shape, or a
  /// reorder-selected stroke - with no confirm dialog, the same immediacy
  /// the eraser tool already gives a stroke it hit-tests directly. Undo
  /// reverses it exactly the way it reverses an erase.
  final ValueChanged<String> onDeleteSelected;

  /// The accessibility fallback's own open state, so the item's label says
  /// which way a tap goes rather than a bare "Activity log" that reads the
  /// same whether it opens or closes the panel.
  final bool activityLogOpen;
  final VoidCallback onToggleActivityLog;

  @override
  State<CanvasOverflowMenu> createState() => _CanvasOverflowMenuState();
}

class _CanvasOverflowMenuState extends State<CanvasOverflowMenu> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  void _paste() {
    _controller.hide();
    widget.onPasteImage();
  }

  void _toggleActivityLog() {
    _controller.hide();
    widget.onToggleActivityLog();
  }

  Future<void> _requestClear() async {
    _controller.hide();
    final count = widget.objectCount.value;
    final confirmed = await confirmDangerousAction(
      context,
      title: 'Clear this canvas?',
      message: count == 1
          ? 'This removes the one object on the canvas for everyone in '
                'this channel. This cannot be undone.'
          : 'This removes all $count objects from the canvas for everyone '
                'in this channel. This cannot be undone.',
      confirmLabel: 'Clear canvas',
      cancelLabel: 'Keep canvas',
    );
    if (confirmed) await widget.onClear();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: (_) => _buildMenu(),
        child: AppIconButton(
          icon: AppIcons.moreVertical,
          semanticLabel: 'More canvas actions',
          tooltip: 'More canvas actions',
          onPressed: _controller.toggle,
        ),
      ),
    );
  }

  void _bringToFront(String objectId) {
    _controller.hide();
    widget.onBringToFront(objectId);
  }

  void _sendToBack(String objectId) {
    _controller.hide();
    widget.onSendToBack(objectId);
  }

  void _delete(String objectId) {
    _controller.hide();
    widget.onDeleteSelected(objectId);
  }

  void _pickShapeKind(CanvasShapeKind kind) {
    _controller.hide();
    widget.onShapeKindChanged(kind);
  }

  static const _shapeKindLabels = {
    CanvasShapeKind.rectangle: ('Rectangle', AppIcons.shapeRectangle),
    CanvasShapeKind.ellipse: ('Ellipse', AppIcons.shapeEllipse),
    CanvasShapeKind.line: ('Line', AppIcons.shapeLine),
    CanvasShapeKind.arrow: ('Arrow', AppIcons.shapeArrow),
  };

  Widget _shortcutHint(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const AppKbd('Ctrl'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            '+',
            style: AppText.micro.copyWith(color: tokens.textDisabled),
          ),
        ),
        const AppKbd('V'),
      ],
    );
  }

  Widget _buildMenu() {
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomRight,
        followerAnchor: Alignment.topRight,
        offset: const Offset(0, 4),
        child: TapRegion(
          onTapOutside: (_) => _controller.hide(),
          // The same keyboard route the message context menu already earned: Tab reaches every item once open, and Escape closes it.
          child: ContextMenuKeyboardScope(
            onDismiss: _controller.hide,
            child: ValueListenableBuilder<String?>(
              valueListenable: widget.selection,
              builder: (context, selected, _) => AppMenu(
                width: 200,
                children: [
                  AppMenuItem(
                    label: 'Paste image',
                    leading: AppIcons.clipboardPaste,
                    // Ctrl+V already works from anywhere in the pane (see canvas_pane.dart's CallbackShortcuts); nothing said so until this hint, and a touch layout drops it, the same "no finger can press it" rule the channel search field's own Ctrl+K hint already follows.
                    trailing: AppTouchTargets.of(context)
                        ? null
                        : _shortcutHint(context),
                    onTap: _paste,
                  ),
                  const AppMenuDivider(),
                  AppMenuItem(
                    label: widget.activityLogOpen
                        ? 'Hide activity log'
                        : 'Show activity log',
                    leading: AppIcons.activityLog,
                    onTap: _toggleActivityLog,
                  ),
                  if (widget.tool == CanvasTool.shape) ...[
                    const AppMenuDivider(),
                    for (final entry in _shapeKindLabels.entries)
                      AppMenuItem(
                        label: entry.value.$1,
                        leading: entry.value.$2,
                        selected: widget.shapeKind == entry.key,
                        onTap: () => _pickShapeKind(entry.key),
                      ),
                  ],
                  if (selected != null) ...[
                    const AppMenuDivider(),
                    AppMenuItem(
                      label: 'Bring to front',
                      leading: AppIcons.bringToFront,
                      onTap: () => _bringToFront(selected),
                    ),
                    AppMenuItem(
                      label: 'Send to back',
                      leading: AppIcons.sendToBack,
                      onTap: () => _sendToBack(selected),
                    ),
                    AppMenuItem(
                      label: 'Delete',
                      leading: AppIcons.delete,
                      tone: AppMenuItemTone.danger,
                      onTap: () => _delete(selected),
                    ),
                  ],
                  if (widget.canManage) ...[
                    const AppMenuDivider(),
                    AppMenuItem(
                      label: 'Clear canvas',
                      leading: AppIcons.delete,
                      tone: AppMenuItemTone.danger,
                      onTap: () => unawaited(_requestClear()),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
