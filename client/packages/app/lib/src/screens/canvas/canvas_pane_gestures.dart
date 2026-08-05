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

  Future<void> _onUndo() async {
    await _ops.undo();
    _refresh();
  }

  Future<void> _onClear() async {
    await _ops.clear(_sync.asOfSeq ?? 0);
    _refresh();
  }

  void _onPointerMoved(Offset world) => _relay.reportLocalPointer(world);

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
