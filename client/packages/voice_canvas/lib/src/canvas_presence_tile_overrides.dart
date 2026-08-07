// SPDX-License-Identifier: Apache-2.0
/// Where a call participant's camera or screen-share tile actually sits on
/// *this* viewer's own canvas, once they have dragged, resized, locked or
/// hidden it away from [CanvasPresenceLayout]'s default arrangement.
///
/// Deliberately local and ephemeral: never written to the op log, never
/// carried on the wire, never shared with the other end of the call. See
/// `docs/decisions/0010-canvas-media-tiles.md` for why a personal,
/// per-viewer arrangement is the answer here rather than a synchronised one.
/// [prune] is what makes "reset on rejoin" (STRATEGY's own phrase for
/// presence objects, extended here from position to the whole override) hold
/// literally: an override keyed to an identity no longer on the call is
/// dropped, so a rejoin starts back at [CanvasPresenceLayout]'s default
/// rather than remembering a drag from a call that already ended.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// One tile's departure from its default position, size and interactivity.
/// [rect] is null until the first drag or resize; a null field always means
/// "use whatever [CanvasPresenceLayout] would otherwise say," never "hide."
@immutable
class CanvasPresenceTileState {
  const CanvasPresenceTileState({
    this.rect,
    this.locked = false,
    this.hidden = false,
    this.sentToBack = false,
  });

  final Rect? rect;

  /// Locked content ignores the pointer entirely - a drawing tool, or a pan,
  /// reaches straight through it - and offers no resize handle; only the
  /// lock control itself stays reachable, so a locked tile is never a dead
  /// end.
  final bool locked;
  final bool hidden;

  /// Whether this tile's own pixels paint behind the drawing surface rather
  /// than above it - see `canvas_presence_backdrop.dart`'s own doc for why
  /// that has to be a second widget rather than a reorder of this one.
  /// Never touches whether the tile's controls hit-test: those stay on
  /// `CanvasPresenceLayer`'s own interactive shell regardless, the same
  /// "never a dead end" guarantee [locked] already makes.
  final bool sentToBack;

  CanvasPresenceTileState copyWith({
    Rect? rect,
    bool? locked,
    bool? hidden,
    bool? sentToBack,
  }) =>
      CanvasPresenceTileState(
        rect: rect ?? this.rect,
        locked: locked ?? this.locked,
        hidden: hidden ?? this.hidden,
        sentToBack: sentToBack ?? this.sentToBack,
      );
}

const _defaultTileState = CanvasPresenceTileState();

/// Keyed by a tile key of the shape `'camera:<identity>'` or
/// `'screen:<identity>'` - an opaque string, the same convention
/// [CanvasPresenceVisibility] and `CanvasPresenceLayout.arrange` already
/// accept unmodified, so nothing here has to know what kind of tile a key
/// names.
class CanvasPresenceTileOverrides extends ChangeNotifier {
  final Map<String, CanvasPresenceTileState> _states = {};

  /// Which tile last had its rect touched, most recent last - a drag or
  /// resize is "bring to front" the same way picking up a real sheet of
  /// paper puts it on top of the pile, so an untouched participant's
  /// default-positioned tile can never sit over one this viewer just moved.
  /// A key absent here has never been touched and paints in [_states]'
  /// insertion order, behind every touched one.
  int _nextZ = 0;
  final Map<String, int> _z = {};

  CanvasPresenceTileState stateFor(String key) =>
      _states[key] ?? _defaultTileState;

  /// This key's own place in the touch order, or null if it has never been
  /// dragged or resized - the render order [CanvasPresenceLayer] sorts by.
  int? zFor(String key) => _z[key];

  void setRect(String key, Rect rect) {
    _states[key] = stateFor(key).copyWith(rect: rect);
    _z[key] = _nextZ++;
    notifyListeners();
  }

  /// Drops a stored position without touching lock or hidden state - the
  /// "reset position" a tile's own controls may offer, distinct from
  /// [prune], which drops the whole entry.
  void clearRect(String key) {
    final current = stateFor(key);
    _states[key] = CanvasPresenceTileState(
      locked: current.locked,
      hidden: current.hidden,
    );
    notifyListeners();
  }

  void setLocked(String key, bool locked) {
    _states[key] = stateFor(key).copyWith(locked: locked);
    notifyListeners();
  }

  void setSentToBack(String key, bool sentToBack) {
    _states[key] = stateFor(key).copyWith(sentToBack: sentToBack);
    notifyListeners();
  }

  void setHidden(String key, bool hidden) {
    _states[key] = stateFor(key).copyWith(hidden: hidden);
    notifyListeners();
  }

  /// Every key currently marked hidden, for a recovery affordance to list -
  /// a hide must stay reversible, or it is a delete wearing a softer name.
  Iterable<String> get hiddenKeys =>
      _states.entries.where((e) => e.value.hidden).map((e) => e.key);

  /// Drops every override whose key is not in [present] - call once per
  /// roster change. A participant who left and later rejoins starts back at
  /// the default arrangement rather than inheriting a drag, a lock or a hide
  /// from a call that has, from this override store's point of view,
  /// already ended.
  void prune(Set<String> present) {
    final before = _states.length;
    _states.removeWhere((key, _) => !present.contains(key));
    _z.removeWhere((key, _) => !present.contains(key));
    if (_states.length != before) notifyListeners();
  }
}
