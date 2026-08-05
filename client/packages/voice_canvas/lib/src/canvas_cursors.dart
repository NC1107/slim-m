// SPDX-License-Identifier: Apache-2.0
/// Remote pointer positions on the canvas: who, where, and how stale.
///
/// A sibling of [CanvasDocument] rather than a part of it: a cursor is
/// presence, not content, and ages out on a caller-driven timer rather than
/// living in the same removed-id, undo-aware model committed ink does.
library;

import 'package:flutter/foundation.dart';

/// One other participant's last-known pointer position, in world
/// coordinates.
@immutable
class CanvasCursor {
  const CanvasCursor({
    required this.id,
    required this.x,
    required this.y,
    required this.label,
    required this.colorIndex,
  });

  /// The user id this cursor belongs to.
  final String id;
  final double x;
  final double y;

  /// What a painter draws beside the pointer glyph.
  final String label;

  /// An index into the caller's own closed cursor-colour set. This package
  /// carries no palette of its own, the same convention every painter here
  /// follows; a caller derives it from [id] (e.g. a hash into the set) and
  /// keeps it stable for the life of a session.
  final int colorIndex;
}

/// Remote pointer positions, keyed by user id.
///
/// There is no server "stopped" frame to remove one by, unlike typing: a
/// cursor is relayed as-is with no matching end signal (see
/// `Event::CanvasCursorMoved`'s own doc, server-side), so staleness is this
/// class's own job via [pruneOlderThan] rather than something a live event
/// can ever tell it to do.
class CanvasCursors extends ChangeNotifier {
  final Map<String, CanvasCursor> _cursors = <String, CanvasCursor>{};
  final Map<String, DateTime> _lastSeen = <String, DateTime>{};

  /// Every remote cursor currently shown.
  Iterable<CanvasCursor> get all => _cursors.values;

  /// Records or refreshes one participant's position.
  void upsert({
    required String id,
    required double x,
    required double y,
    required String label,
    required int colorIndex,
    DateTime? now,
  }) {
    _cursors[id] = CanvasCursor(
      id: id,
      x: x,
      y: y,
      label: label,
      colorIndex: colorIndex,
    );
    _lastSeen[id] = now ?? DateTime.now();
    notifyListeners();
  }

  /// Drops every cursor not refreshed within [ttl] of [now].
  ///
  /// Meant to be called from a caller-owned periodic timer; nothing in this
  /// class schedules its own, since a `Timer.periodic` inside a
  /// `ChangeNotifier` with no `dispose` caller in a widget test is exactly
  /// the uncancellable-timer trap this project has already hit once (see
  /// `voice_roster.dart`'s own history).
  void pruneOlderThan(Duration ttl, {DateTime? now}) {
    final cutoff = (now ?? DateTime.now()).subtract(ttl);
    final stale = _lastSeen.entries
        .where((entry) => entry.value.isBefore(cutoff))
        .map((entry) => entry.key)
        .toList(growable: false);
    if (stale.isEmpty) return;
    for (final id in stale) {
      _cursors.remove(id);
      _lastSeen.remove(id);
    }
    notifyListeners();
  }

  /// Drops one cursor immediately, e.g. once its author is blocked.
  void remove(String id) {
    if (_cursors.remove(id) == null) return;
    _lastSeen.remove(id);
    notifyListeners();
  }

  /// Drops every cursor, e.g. when the pane holding this document unmounts.
  void clear() {
    if (_cursors.isEmpty) return;
    _cursors.clear();
    _lastSeen.clear();
    notifyListeners();
  }
}
