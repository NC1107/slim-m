// SPDX-License-Identifier: Apache-2.0
/// Canvas objects, as a viewport read returns them.
library;

/// One object on a channel's canvas.
class CanvasObject {
  const CanvasObject({
    required this.id,
    required this.kind,
    required this.zIndex,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.props,
    required this.authorId,
    required this.seq,
    required this.createdAt,
  });

  final String id;

  /// `stroke`, `image`, `gif` or `window`. Deliberately a String: a client too
  /// old to know a kind should skip that object, not fail to parse the region.
  final String kind;

  final int zIndex;
  final double x;
  final double y;
  final double w;
  final double h;

  /// Kind-specific payload, opaque here.
  final Map<String, dynamic> props;

  /// Null once the author's account has been deleted.
  final String? authorId;

  /// Per-channel order key, and the cursor for a delta read.
  final int seq;
  final int createdAt;

  factory CanvasObject.fromJson(Map<String, dynamic> json) => CanvasObject(
        id: json['id'] as String,
        kind: json['kind'] as String,
        zIndex: json['z_index'] as int,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        w: (json['w'] as num).toDouble(),
        h: (json['h'] as num).toDouble(),
        props: (json['props'] as Map<String, dynamic>?) ?? const {},
        authorId: json['author_id'] as String?,
        seq: json['seq'] as int,
        createdAt: json['created_at'] as int,
      );
}

/// The answer to one viewport read.
class CanvasViewport {
  const CanvasViewport({
    required this.objects,
    required this.hasMore,
    required this.latestSeq,
  });

  final List<CanvasObject> objects;

  /// More objects intersect the region than the limit allowed. There is no
  /// stable cursor across a region query, so the answer is a smaller region
  /// rather than a next page.
  final bool hasMore;

  /// The channel's highest assigned canvas seq, to send back as `afterSeq`.
  final int latestSeq;

  factory CanvasViewport.fromJson(Map<String, dynamic> json) => CanvasViewport(
        objects: (json['objects'] as List<dynamic>)
            .map((o) => CanvasObject.fromJson(o as Map<String, dynamic>))
            .toList(),
        hasMore: json['has_more'] as bool,
        latestSeq: json['latest_seq'] as int,
      );
}

/// A rectangle in world coordinates.
class CanvasRect {
  const CanvasRect({
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
  });

  final double minX;
  final double minY;
  final double maxX;
  final double maxY;
}
