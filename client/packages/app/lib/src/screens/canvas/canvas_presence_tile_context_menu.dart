// SPDX-License-Identifier: Apache-2.0
/// The menu a right-click on a presence tile opens - the same verbs
/// `TileControls`'s hover row already exposes, reached without hovering or
/// pressing first. `CanvasPresenceTileMenuController` is the seam:
/// `canvas_presence_tile.dart`'s own `onSecondaryTapUp` calls
/// [CanvasPresenceTileMenuController.open] with the pointer that fired, and
/// this widget - mounted once per tile, invisible until shown - does the
/// rest.
///
/// A controller rather than a `GlobalKey`: a tile rebuilds on every drag
/// frame, and a fresh key on each of those rebuilds would tear down and
/// remount the `OverlayPortal` this widget owns mid-gesture, dropping
/// whatever menu it was showing along with it.
///
/// The gesture that opens this is still exactly the `onSecondaryTapUp`
/// `canvas_presence_tile.dart`'s own `GestureDetector` already had, and that
/// detector is still `HitTestBehavior.opaque` - a right-click over a tile
/// keeps consuming the event before it ever reaches a canvas object
/// underneath, the reason that handler existed as a no-op in the first
/// place. Only the callback body changed. See
/// `canvas_presence_tile_context_menu_test.dart`.
///
/// No keyboard route opens this menu, unlike `ContextMenuRegion`'s context-
/// menu-key fallback: a keyboard user already reaches every verb here
/// directly, since `canvas_presence_tile.dart`'s own focus-reveal shows
/// `TileControls`'s row - this menu's only content - the moment the tile
/// gains focus. Escape still closes the menu once a mouse has opened it,
/// through the same `ContextMenuKeyboardScope` every other menu in this app
/// uses.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../../widgets/context_menu_focus.dart';
import '../../widgets/message_context_menu_layout.dart';

/// Opens [CanvasPresenceTileContextMenu] from wherever the right-click that
/// should open it actually happens - `canvas_presence_tile.dart`'s own
/// gesture handler, not this file.
class CanvasPresenceTileMenuController {
  _CanvasPresenceTileContextMenuState? _state;

  void open(Offset globalPosition) => _state?._open(globalPosition);
}

/// Renders nothing until [CanvasPresenceTileMenuController.open] is called.
/// Mount one alongside a tile's own content; its position in the tree does
/// not matter since it paints only through its `OverlayPortal`.
class CanvasPresenceTileContextMenu extends StatefulWidget {
  const CanvasPresenceTileContextMenu({
    super.key,
    required this.controller,
    required this.locked,
    required this.sentToBack,
    this.onToggleLocked,
    this.onToggleSentToBack,
    required this.onHide,
    this.onExpand,
  });

  final CanvasPresenceTileMenuController controller;
  final bool locked;
  final bool sentToBack;

  /// Null renders no row for this verb at all, matching `TileControls`'s own
  /// null-means-no-button shape - this menu offers exactly its verbs and
  /// nothing else, so an avatar-only tile's menu is just "Hide".
  final VoidCallback? onToggleLocked;
  final VoidCallback? onToggleSentToBack;
  final VoidCallback onHide;
  final VoidCallback? onExpand;

  @override
  State<CanvasPresenceTileContextMenu> createState() =>
      _CanvasPresenceTileContextMenuState();
}

class _CanvasPresenceTileContextMenuState
    extends State<CanvasPresenceTileContextMenu> {
  final _overlay = OverlayPortalController();
  Offset _anchor = Offset.zero;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
  }

  @override
  void didUpdateWidget(CanvasPresenceTileContextMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller._state = null;
      widget.controller._state = this;
    }
  }

  @override
  void dispose() {
    if (identical(widget.controller._state, this)) {
      widget.controller._state = null;
    }
    super.dispose();
  }

  void _open(Offset globalPosition) {
    final overlayObject = Overlay.of(context).context.findRenderObject();
    final overlay = overlayObject is RenderBox ? overlayObject : null;
    if (overlay == null) return;
    setState(() => _anchor = overlay.globalToLocal(globalPosition));
    _overlay.show();
  }

  void _close() => _overlay.hide();

  void _run(VoidCallback? action) {
    _close();
    action?.call();
  }

  List<Widget> get _items => [
    if (widget.onExpand case final onExpand?)
      AppMenuItem(
        label: 'Full screen',
        leading: AppIcons.expand,
        onTap: () => _run(onExpand),
      ),
    if (widget.onToggleLocked case final onToggleLocked?)
      AppMenuItem(
        label: widget.locked ? 'Unlock' : 'Lock in place',
        leading: widget.locked ? AppIcons.tileUnlocked : AppIcons.tileLocked,
        onTap: () => _run(onToggleLocked),
      ),
    if (widget.onToggleSentToBack case final onToggleSentToBack?)
      AppMenuItem(
        label: widget.sentToBack ? 'Bring to front' : 'Send to back',
        leading: widget.sentToBack
            ? AppIcons.bringToFront
            : AppIcons.sendToBack,
        onTap: () => _run(onToggleSentToBack),
      ),
    AppMenuItem(
      label: 'Hide on your canvas',
      leading: AppIcons.tileHide,
      onTap: () => _run(widget.onHide),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: (context) => Positioned.fill(
        child: CustomSingleChildLayout(
          delegate: MessageMenuLayout(
            anchor: _anchor,
            padding:
                MediaQuery.paddingOf(context) +
                const EdgeInsets.all(menuScreenMargin),
          ),
          child: TapRegion(
            onTapOutside: (_) => _close(),
            child: ContextMenuKeyboardScope(
              onDismiss: _close,
              child: AppMenu(width: 220, children: _items),
            ),
          ),
        ),
      ),
      child: const SizedBox.shrink(),
    );
  }
}
