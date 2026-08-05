// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// Reading a region of a channel's canvas and placing objects on it, the
/// `canvas` tag.
extension SlimmApiCanvas on SlimmApi {
  /// Every live object intersecting [region], in paint order.
  ///
  /// Pass [previous] and [afterSeq] together while panning and the answer is a
  /// delta: what the new region holds that the old one did not, plus anything
  /// in both that is newer than the cursor. Omit them for a cold fetch.
  ///
  /// The delta reports arrivals, not removals. A soft delete does not advance
  /// an object's seq, so no cursor here can carry one; removals come from the
  /// canvas op stream.
  Future<CanvasViewport> canvasViewport(
    String channelId, {
    required CanvasRect region,
    CanvasRect? previous,
    int? afterSeq,
    int? limit,
  }) async {
    final query = <String, String>{
      'min_x': '${region.minX}',
      'min_y': '${region.minY}',
      'max_x': '${region.maxX}',
      'max_y': '${region.maxY}',
      if (previous != null) ...{
        'prev_min_x': '${previous.minX}',
        'prev_min_y': '${previous.minY}',
        'prev_max_x': '${previous.maxX}',
        'prev_max_y': '${previous.maxY}',
      },
      if (afterSeq != null) 'after_seq': '$afterSeq',
      if (limit != null) 'limit': '$limit',
    };
    final json = await _send(
      'GET',
      '/channels/$channelId/canvas/objects',
      query: query,
    );
    return CanvasViewport.fromJson(json as Map<String, dynamic>);
  }

  /// Places one object, idempotent by [id].
  ///
  /// [id] is a client-generated UUIDv7 and is the idempotency key, exactly as
  /// a message id is: replaying it answers with the stored row, its original
  /// seq intact, and broadcasts nothing, so a retry after a lost response is
  /// safe. [x] and [y] are the top-left corner in world coordinates and [w]
  /// and [h] the extents, neither over 8192.
  ///
  /// [props] is kind-specific and opaque to the server, capped at 4 KiB
  /// serialized. A stroke's `points` are relative to [x] and [y].
  Future<CanvasObject> placeCanvasObject(
    String channelId, {
    required String id,
    required String kind,
    required double x,
    required double y,
    required double w,
    required double h,
    required Map<String, dynamic> props,
  }) async {
    final json = await _send(
      'POST',
      '/channels/$channelId/canvas/objects',
      body: {
        'id': id,
        'kind': kind,
        'x': x,
        'y': y,
        'w': w,
        'h': h,
        'props': props,
      },
    );
    return CanvasObject.fromJson(json as Map<String, dynamic>);
  }

  /// Submits a canvas mutation - `remove`, `clear`, `restore`, `move`, or
  /// `reorder` - idempotent by [id] exactly as [placeCanvasObject] is: a
  /// replay answers with the stored op, `fresh: false`, and publishes
  /// nothing.
  ///
  /// Exactly one of [objectIds] (`remove`), [beforeSeq] (`clear`),
  /// [targetOp] (`restore`), [objectId] plus [x]/[y]/[w]/[h] (`move`), or
  /// [objectId] plus [zIndex] (`reorder`) is meaningful for a given [kind];
  /// the server rejects any other combination with a 400.
  Future<CanvasOpResult> submitCanvasOp(
    String channelId, {
    required String id,
    required String kind,
    List<String>? objectIds,
    int? beforeSeq,
    String? targetOp,
    String? objectId,
    double? x,
    double? y,
    double? w,
    double? h,
    int? zIndex,
  }) async {
    final json = await _send(
      'POST',
      '/channels/$channelId/canvas/ops',
      body: {
        'id': id,
        'kind': kind,
        if (objectIds != null) 'object_ids': objectIds,
        if (beforeSeq != null) 'before_seq': beforeSeq,
        if (targetOp != null) 'target_op': targetOp,
        if (objectId != null) 'object_id': objectId,
        if (x != null) 'x': x,
        if (y != null) 'y': y,
        if (w != null) 'w': w,
        if (h != null) 'h': h,
        if (zIndex != null) 'z_index': zIndex,
      },
    );
    return CanvasOpResult.fromJson(json as Map<String, dynamic>);
  }

  /// Pages the canvas op stream from [afterSeq] (exclusive): the catch-up
  /// feed a client reconciling after a drop or a reconnect reads, rather
  /// than a full viewport re-read.
  Future<CanvasOpsPage> canvasOps(
    String channelId, {
    required int afterSeq,
    int? limit,
  }) async {
    final query = <String, String>{
      'after_seq': '$afterSeq',
      if (limit != null) 'limit': '$limit',
    };
    final json = await _send(
      'GET',
      '/channels/$channelId/canvas/ops',
      query: query,
    );
    return CanvasOpsPage.fromJson(json as Map<String, dynamic>);
  }
}
