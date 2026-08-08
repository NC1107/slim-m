// SPDX-License-Identifier: Apache-2.0
/// Reading and writing the shared, persistent half of a media tile's state
/// - position, size, lock and depth - which the server remembers per
/// channel now (decision 0010's reversal). `hidden` never passes through
/// here: it stays the one field `CanvasPresenceTileOverrides` keeps purely
/// local, exactly as it always has.
///
/// One cold fetch on opening the canvas, then live `canvas.media_slot
/// .changed` frames keep the picture current - the same "cold fetch, then
/// live" shape the viewport read and the canvas op stream already use.
library;

import 'dart:ui';

import 'package:slimm_api/api.dart' as api;
import 'package:slimm_voice_canvas/voice_canvas.dart';

import 'canvas_presence_geometry.dart'
    show presenceTileIdentity, presenceTileKind;

class CanvasMediaSlotSync {
  CanvasMediaSlotSync({
    required this.channelId,
    required this.client,
    required this.overrides,
  });

  final String channelId;
  final api.SlimmApi client;
  final CanvasPresenceTileOverrides overrides;

  /// Every slot this channel's canvas currently remembers, applied once.
  /// Failures are silent and leave every tile at its default arrangement -
  /// the same degrade a lost viewport read already falls back to, rather
  /// than blocking the canvas on this one read.
  Future<void> fetch() async {
    final api.CanvasMediaSlotPage page;
    try {
      page = await client.canvasMediaSlots(channelId);
    } on api.ApiException {
      return;
    }
    for (final slot in page.slots) {
      overrides.applyServer(
        '${slot.kind}:${slot.userId}',
        rect: Rect.fromLTWH(slot.x, slot.y, slot.w, slot.h),
        locked: slot.locked,
        sentToBack: slot.sentToBack,
      );
    }
  }

  /// Sends [key]'s now-settled [rect], plus whatever `overrides.stateFor(key)`
  /// currently says about lock and depth, to the server. Best-effort and
  /// fire-and-forget, the same shape `VoiceController.leave()`'s own
  /// heartbeat call already uses: a failed write leaves the caller's own
  /// optimistic local update standing, with nowhere better to report a
  /// canvas drag's own failure than a `SnackBar` nobody asked for.
  Future<void> commit(String key, Rect rect) async {
    final state = overrides.stateFor(key);
    try {
      await client.putCanvasMediaSlot(
        channelId,
        kind: presenceTileKind(key),
        userId: presenceTileIdentity(key),
        x: rect.left,
        y: rect.top,
        w: rect.width,
        h: rect.height,
        locked: state.locked,
        sentToBack: state.sentToBack,
      );
    } on api.ApiException {
      // Best-effort; see this method's own doc.
    }
  }

  /// Applies a live `canvas.media_slot.changed` frame naming this channel.
  void applyRemote(api.CanvasMediaSlotChanged event) {
    if (event.channelId != channelId) return;
    overrides.applyServer(
      '${event.kind}:${event.userId}',
      rect: Rect.fromLTWH(event.x, event.y, event.w, event.h),
      locked: event.locked,
      sentToBack: event.sentToBack,
    );
  }
}
