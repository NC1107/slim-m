// SPDX-License-Identifier: Apache-2.0
part of 'canvas_pane.dart';

/// The select tool, undo, clear and the camera-bubble roster: split out of
/// `_CanvasPaneState` once this fix pushed the file past the 500-line hard
/// limit, the same reason `canvas_ops_controller_reorder.dart` splits its
/// own class this way - an extension in a `part of` file, not a second
/// class, since these all need `_CanvasPaneState`'s own fields.
extension _CanvasPaneGestures on _CanvasPaneState {
  /// Leaving the select tool deselects, so the outline and its resize
  /// handles do not linger over a selection nothing can act on any more
  /// while the pen or eraser is active.
  void _onToolChanged(CanvasTool tool) {
    if (tool != CanvasTool.select) _document.selectedObjectId.value = null;
    _refresh(() => _tool = tool);
  }

  /// Opens the note sheet, and places the note only once it comes back with
  /// real text - nothing is sent, and nothing shows on the shared canvas,
  /// for a sheet the person cancelled or left blank. [_selectPlaced] is what
  /// closes it out.
  Future<void> _onNotePlace(Offset world) async {
    final text = await showCanvasNoteSheet(context);
    if (text == null || !_mounted) return;
    final placed = await _quickPlacement.placeNote(
      world,
      text,
      onError: (message) => _refresh(() => _error = message),
    );
    if (placed != null) _selectPlaced(placed.id);
  }

  /// Places a shape of the bar's own currently-picked kind at once - no
  /// sheet, since a shape carries no text to type.
  ///
  /// Used to stay on the shape tool afterward rather than switching to
  /// select, on the theory that placing several shapes of the same kind in
  /// a row is a normal thing to want and switching tools after every tap
  /// would make that tedious. That theory is what report 3 in the backlog
  /// channel found wrong in practice: staying on the shape tool left a
  /// freshly placed shape with no way to resize it short of a manual switch
  /// to Move first, which is worse than the rapid-placement convenience it
  /// was bought with. [_selectPlaced] now matches the note and paste paths.
  Future<void> _onShapePlace(Offset world) async {
    final placed = await _quickPlacement.placeShape(
      world,
      _shapeKind,
      onError: (message) => _refresh(() => _error = message),
    );
    if (placed != null) _selectPlaced(placed.id);
  }

  /// After placing a new object - a placed note, a placed shape, or a
  /// pasted image - the thing just made is the thing selected, with its
  /// resize handles already live and the surface already in Move mode: no
  /// separate switch is needed before it can be resized.
  ///
  /// Chosen over having the placement gesture itself carry a size (drag to
  /// place, sized as dragged) because it is the smaller change: it needs no
  /// new coexistence with the pinch-deferral already guarding a placement
  /// tool's own first pointer-down (see `_resolvePendingPlacement`'s doc in
  /// `canvas_surface_gestures.dart`), and no new "what does a zero-length
  /// drag produce" case to define. The cost is real and named rather than
  /// hidden: a person placing several same-sized shapes in a row now
  /// switches tools once per shape rather than never, where drag-to-place
  /// would have kept the rapid-placement flow at the cost of a heavier
  /// gesture change.
  void _selectPlaced(String objectId) {
    if (!_mounted) return;
    _document.selectedObjectId.value = objectId;
    _refresh(() => _tool = CanvasTool.select);
  }

  void _onSelectStart(Offset world) {
    final me = ref.read(meProvider).valueOrNull;
    _ops.beginSelect(
      world,
      manageCanvas: me?.permissions.hasPermission(Perm.manageCanvas) ?? false,
      selfId: me?.id,
    );
  }

  /// Aspect locks by default; holding Shift frees it. Read fresh on every
  /// drag point rather than once at [_onSelectStart], so releasing the key
  /// mid-drag takes effect immediately rather than on the next gesture.
  void _onSelectDrag(Offset world) => _ops.dragSelect(
    world,
    lockAspect: !HardwareKeyboard.instance.isShiftPressed,
  );

  Future<void> _onSelectEnd() async {
    await _ops.endSelect();
    _refresh();
  }

  Future<void> _onBringToFront(String objectId) async {
    await _ops.bringToFront(objectId);
    _refresh();
  }

  Future<void> _onSendToBack(String objectId) async {
    await _ops.sendToBack(objectId);
    _refresh();
  }

  Future<void> _onDeleteSelected(String objectId) async {
    await _ops.deleteSelected(objectId);
    _refresh();
  }

  Future<void> _onUndo() async {
    await _ops.undo();
    _refresh();
  }

  Future<void> _onClear() async {
    await _ops.clear(_sync.asOfSeq ?? 0);
    _refresh();
  }

  /// Jumps the camera back to the world origin - a plain camera move, so it
  /// needs no `setState` any more than a scroll or a pinch does. See
  /// `worldLimit`'s own doc for the "no route back" gap this closes.
  void _onRecenter() => _document.setCamera(const Camera());

  /// Delete/Backspace over the current Move-tool selection, the desktop
  /// convention every other drawing surface honours - the overflow menu's
  /// own "Delete" item is the only route without this, one that needs
  /// finding rather than reaching for the key a person already expects.
  void _onDeleteKey() {
    final selected = _document.selectedObjectId.value;
    if (selected != null) unawaited(_onDeleteSelected(selected));
  }

  void _onPointerMoved(Offset world) => _relay.reportLocalPointer(world);

  /// A remote cursor's label as of the last resolved answer, kicking off a
  /// fetch for an id this session has not asked about yet - the same
  /// resolve-then-fall-back order `authorLabel` uses for a message author,
  /// minus the local `authorDisplayName` cache a cursor has no row to carry.
  String _cursorLabel(String userId) {
    final profiles = ref.read(batchProfilesControllerProvider);
    resolveAuthorProfiles(ref, [userId]);
    if (profiles.containsKey(userId)) {
      return profiles[userId]?.displayName ?? 'Deleted user';
    }
    return 'Someone';
  }

  /// Who to show on the canvas as a camera bubble: nobody, unless this
  /// device itself has joined a call in this exact channel - a canvas
  /// viewer who has not joined the call has no LiveKit room to render a
  /// live texture from at all (`VoiceSession.cameraViewFor` answers nothing
  /// without one), so there is no video to lay out for anybody in that
  /// case, not even for participants known some other way.
  List<VoiceParticipant> _callParticipants() {
    final voice = ref.watch(voiceControllerProvider);
    if (voice.channelId != widget.channelId) return const [];
    final blocks = ref.watch(blocksProvider);
    return voice.participants
        .where((p) => !blocks.contains(p.identity))
        .toList(growable: false);
  }
}
