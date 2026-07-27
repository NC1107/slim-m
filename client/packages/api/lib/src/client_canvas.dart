// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// Reading a region of a channel's canvas, the `canvas` tag.
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
}
