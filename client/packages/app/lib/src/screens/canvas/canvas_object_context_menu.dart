// SPDX-License-Identifier: Apache-2.0
/// A right-click over a canvas object: bring to front, send to back, delete
/// - the same three verbs the overflow menu already offers a selection,
/// reached directly at the object under the cursor instead of a
/// select-then-open-the-overflow-menu round trip.
///
/// **Why not `ContextMenuRegion`.** That widget wraps one static child as
/// the gesture target and opens on tap-DOWN, both wrong here: a canvas
/// object is painted, not a widget, so the target has to be resolved by
/// hit-testing at the pointer's own position rather than fixed at
/// construction; and opening on tap-down would show a menu before a
/// competing right-drag pan (built separately, on this same surface) ever
/// gets to declare itself a drag. This widget reuses everything about
/// `ContextMenuRegion` that does transfer - [MessageMenuLayout]'s anchored
/// positioning, [ContextMenuKeyboardScope]'s Escape/Tab route, [AppMenu]'s
/// body - and only rebuilds the gesture detection and target resolution
/// that a painted surface actually needs.
///
/// **Tap-up, not tap-down, is what makes this immune to a right-drag pan
/// on the same surface, regardless of how that pan turns out to be built.**
/// [GestureDetector.onSecondaryTapUp] only fires once a secondary-button
/// press releases without exceeding the platform's own tap slop; a real
/// drag either cancels this tap outright (if the pan is a competing
/// `GestureRecognizer` restricted to the same button, Flutter's own arena
/// resolves the two exactly the way a tap and a pan already disambiguate
/// anywhere else in this codebase) or never registers with it at all (if
/// the pan instead reads `event.buttons` off the surface's own raw
/// `Listener`, which this widget's tap recognizer neither blocks nor is
/// blocked by - a `Listener` and a `GestureDetector` at the same point both
/// see every raw event independently). Either way there is no window in
/// which a drag can leave a menu open behind it.
///
/// **The gesture layer is deliberately button-scoped rather than
/// button-blind.** Only `onSecondaryTapUp` is wired, and
/// `TapGestureRecognizer.isPointerAllowed` (read from source, not assumed)
/// refuses a primary-button pointer outright the moment no primary
/// callback is set - so this layer cannot compete for, delay, or otherwise
/// affect an ordinary left-button draw, erase or select gesture on the
/// surface beneath it.
///
/// **Empty canvas does nothing**, deliberately: there is no established
/// "act on this exact point" set of canvas-wide actions to justify a menu
/// where one was never asked for, the toolbar's overflow menu already
/// reaches everything canvas-wide (paste image, recenter, clear) from one
/// place regardless of where the cursor happens to be, and popping a menu
/// from a click that turns out to have been the start of a pan is worse
/// than popping none. Revisiting this (a paste-at-cursor item, say) is real
/// future work, not something this file backs into.
///
/// **Deliberately duplicated with the overflow menu's own selection-gated
/// items, not moved.** Touch has no right-click at all, so the overflow
/// menu - reachable from the bar on every platform - is the only route a
/// touch user has to bring-to-front/send-to-back/delete; removing them
/// there to avoid the overlap would be a real regression for touch, not a
/// simplification. Teaching a long press to open this same menu was
/// considered and rejected: the surface's raw `Listener` already reacts to
/// pointer-down immediately for every tool (starting a stroke draft, an
/// erase, a placement), so a held touch would draw or place *and* pop a
/// menu 500ms later, which needs its own design pass this report did not
/// ask for.
///
/// **Keyboard and screen-reader route: `CanvasSelectionSemantics`, not a
/// tab stop of this widget's own.** A canvas object has no focus node to
/// hang `ContextMenuFocus`'s row-tab-stop model on; the one accessibility
/// node an object already gets once selected is exactly where a custom
/// "open its actions" route belongs instead. [CanvasObjectMenuRequests] is
/// the small bus that carries that request here with no pointer position
/// behind it - the same gap `ContextMenuRegion`'s own context-menu-key
/// fallback covers for a message row, anchored here at the selected
/// object's own screen-space centre rather than a fixed corner, since
/// unlike a row this widget always knows exactly what it is opening for.
///
/// **`excludeFromSemantics: true` on the hit-catcher, and it is load-bearing
/// rather than tidiness.** Wiring `onSecondaryTapUp` alone still makes
/// `RawGestureDetector` build a `TapGestureRecognizer` (needed to detect any
/// tap variant, secondary included), and Flutter's own default semantics
/// delegate (`_DefaultSemanticsGestureDelegate._getTapHandler`, read from
/// the framework source rather than assumed) exposes `SemanticsAction.tap`
/// the moment *any* `TapGestureRecognizer` exists, regardless of which tap
/// callback it actually carries. Without the exclusion this childless
/// `SizedBox.expand()` became a full-canvas `role="button"` node the moment
/// semantics were ever engaged (a screen reader, or anything else that
/// turns Flutter's accessibility tree on) - Flutter's web renderer sets
/// `pointer-events: all` on any such actionable node, which sits in front
/// of `CanvasSurface` and silently swallows every draw, erase, select and
/// placement gesture with no visible error, since the recognizer this
/// invented "tap" would actually invoke has no `onTap` of its own to call.
/// The accessible route to these three actions was never this node's job in
/// the first place - see the paragraph above - so nothing is lost by
/// telling Flutter this hit-catcher has no accessibility meaning of its
/// own.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_voice_canvas/voice_canvas.dart';

import '../../widgets/context_menu_focus.dart';
import '../../widgets/message_context_menu_layout.dart';

/// A request to open [CanvasObjectContextMenu] for a specific object with no
/// pointer position behind it - see this file's own doc for the keyboard and
/// screen-reader route this exists for.
///
/// Notifies unconditionally on every [request] call, never gated on whether
/// [objectId] actually changed: a `ValueNotifier`'s equality gate would
/// silently swallow a second ask for the same object (open, dismiss, ask
/// again), the same trap `canvas_activity_log.dart`'s own `announcementTick`
/// doc comment already names for an identical shape.
class CanvasObjectMenuRequests extends ChangeNotifier {
  String? objectId;

  void request(String objectId) {
    this.objectId = objectId;
    notifyListeners();
  }
}

class CanvasObjectContextMenu extends StatefulWidget {
  const CanvasObjectContextMenu({
    super.key,
    required this.document,
    required this.canManage,
    required this.selfId,
    required this.requests,
    required this.onToolChanged,
    required this.onBringToFront,
    required this.onSendToBack,
    required this.onDeleteSelected,
  });

  final CanvasDocument document;

  /// Whether the caller holds MANAGE_CANVAS - widens which objects a
  /// right-click can resolve a target from, the same bit
  /// `CanvasOpsControllerSelect.beginSelect` reads for the identical reason.
  final bool canManage;
  final String? selfId;
  final CanvasObjectMenuRequests requests;

  /// Switches the surface to the Move tool once a target resolves, so the
  /// object a right-click just found is immediately draggable and
  /// resizable with no separate tool switch - the same closing move
  /// `canvas_pane_gestures.dart`'s `_selectPlaced` makes after placing one.
  final ValueChanged<CanvasTool> onToolChanged;
  final ValueChanged<String> onBringToFront;
  final ValueChanged<String> onSendToBack;
  final ValueChanged<String> onDeleteSelected;

  @override
  State<CanvasObjectContextMenu> createState() =>
      _CanvasObjectContextMenuState();
}

class _CanvasObjectContextMenuState extends State<CanvasObjectContextMenu> {
  final _controller = OverlayPortalController();
  Offset _anchor = Offset.zero;
  String? _target;

  @override
  void initState() {
    super.initState();
    widget.requests.addListener(_onRequest);
  }

  @override
  void dispose() {
    widget.requests.removeListener(_onRequest);
    super.dispose();
  }

  void _onRequest() {
    final id = widget.requests.objectId;
    if (id != null) _openFor(id, pointerGlobal: null);
  }

  bool _allowed(CanvasStroke stroke) =>
      widget.canManage ||
      (stroke.authorId != null && stroke.authorId == widget.selfId);

  /// Box kinds first, a stroke only if no box was hit - the exact precedence
  /// `beginSelect` already establishes for the select tool's own pointer
  /// down, so a right-click resolves to the same target a left-click select
  /// would have.
  String? _hitTest(Offset world) =>
      hitTestBoxAt(widget.document, world, allowed: _allowed) ??
      hitTestStroke(widget.document, world, allowed: _allowed);

  Offset _toWorld(Offset local) {
    final camera = widget.document.camera;
    return Offset(
      camera.x + local.dx / camera.zoom,
      camera.y + local.dy / camera.zoom,
    );
  }

  void _onSecondaryTapUp(TapUpDetails details) {
    final id = _hitTest(_toWorld(details.localPosition));
    if (id != null) _openFor(id, pointerGlobal: details.globalPosition);
  }

  void _openFor(String id, {required Offset? pointerGlobal}) {
    widget.document.selectedObjectId.value = id;
    widget.onToolChanged(CanvasTool.select);
    setState(() {
      _target = id;
      _anchor = _anchorOffset(id, pointerGlobal);
    });
    _controller.show();
  }

  /// Overlay-local, matching what [MessageMenuLayout] expects: a real
  /// pointer position converts global-to-local against the overlay itself,
  /// the same conversion `ContextMenuRegion` uses for a right-click; a
  /// keyboard-driven request with no pointer instead anchors at the
  /// selected object's own on-screen centre, converted through this
  /// widget's own box rather than a fixed corner, since unlike a message
  /// row this widget always knows exactly which object it is opening for.
  Offset _anchorOffset(String id, Offset? pointerGlobal) {
    final overlayObject = Overlay.of(context).context.findRenderObject();
    final overlay = overlayObject is RenderBox ? overlayObject : null;
    if (overlay == null) return Offset.zero;
    if (pointerGlobal != null) return overlay.globalToLocal(pointerGlobal);
    final boxObject = context.findRenderObject();
    final box = boxObject is RenderBox ? boxObject : null;
    final bounds = widget.document.objectBounds(id);
    if (box == null || bounds == null) return Offset.zero;
    final camera = widget.document.camera;
    final center = Offset(
      (bounds.x + bounds.w / 2 - camera.x) * camera.zoom,
      (bounds.y + bounds.h / 2 - camera.y) * camera.zoom,
    );
    return box.localToGlobal(center, ancestor: overlay);
  }

  void _close() => _controller.hide();

  void _bringToFront() {
    final id = _target;
    _close();
    if (id != null) widget.onBringToFront(id);
  }

  void _sendToBack() {
    final id = _target;
    _close();
    if (id != null) widget.onSendToBack(id);
  }

  void _delete() {
    final id = _target;
    _close();
    if (id != null) widget.onDeleteSelected(id);
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _controller,
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
              child: AppMenu(
                width: 200,
                children: [
                  AppMenuItem(
                    label: 'Bring to front',
                    leading: AppIcons.bringToFront,
                    onTap: _bringToFront,
                  ),
                  AppMenuItem(
                    label: 'Send to back',
                    leading: AppIcons.sendToBack,
                    onTap: _sendToBack,
                  ),
                  AppMenuItem(
                    label: 'Delete',
                    leading: AppIcons.delete,
                    tone: AppMenuItemTone.danger,
                    onTap: _delete,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      // translucent, not the default: a childless SizedBox registers no hit under deferToChild, and opaque would stop every primary-button event reaching CanvasSurface beneath.
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: _onSecondaryTapUp,
        // Load-bearing, not tidiness - see this file's own library doc.
        excludeFromSemantics: true,
        child: const SizedBox.expand(),
      ),
    );
  }
}
