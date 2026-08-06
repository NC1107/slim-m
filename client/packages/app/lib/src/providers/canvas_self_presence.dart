// SPDX-License-Identifier: Apache-2.0
/// Whether the caller's own camera bubble is shown on the Voice Canvas, and
/// which corner it rests in.
///
/// A device-wide view preference, the same shelf [themeControllerProvider]
/// and the voice settings keys already use (`providers.dart`'s own doc names
/// them), not the per-account namespacing `personal_space_visibility.dart`
/// needs: that preference is about one account's own channel list, where this
/// one is about how this device likes to see itself on any canvas, on any
/// account signed into it. There is nothing account-specific to leak by
/// sharing it.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// The `SharedPreferences` keys, in [preferencesProvider], following the
/// existing `slimm.<area>.<thing>` convention.
const canvasSelfBubbleHiddenKey = 'slimm.canvas.self_bubble.hidden';
const canvasSelfBubbleCornerKey = 'slimm.canvas.self_bubble.corner';

/// The four resting spots a self bubble may snap to. Corner-anchored rather
/// than a stored `Offset`, because a corner recomputes its own pixel position
/// from whatever size the canvas pane is now - a remembered `(x, y)` would
/// drift toward, or past, an edge the first time the pane is narrower than
/// when it was dragged.
enum CanvasSelfBubbleCorner { topLeft, topRight, bottomLeft, bottomRight }

class CanvasSelfPresenceState {
  const CanvasSelfPresenceState({
    this.hidden = false,
    this.corner = CanvasSelfBubbleCorner.bottomRight,
  });

  final bool hidden;

  /// Bottom-right by default: the corner a video call's own self-view sits
  /// in on every mainstream call app, so it starts somewhere already
  /// familiar rather than needing to be found.
  final CanvasSelfBubbleCorner corner;

  CanvasSelfPresenceState copyWith({
    bool? hidden,
    CanvasSelfBubbleCorner? corner,
  }) => CanvasSelfPresenceState(
    hidden: hidden ?? this.hidden,
    corner: corner ?? this.corner,
  );
}

class CanvasSelfPresenceController
    extends StateNotifier<CanvasSelfPresenceState> {
  CanvasSelfPresenceController(this._ref)
    : super(const CanvasSelfPresenceState()) {
    ready = _load();
  }

  final Ref _ref;

  /// Bumped by every explicit [setHidden]/[setCorner] call, so a load still
  /// in flight when the very first one of those lands does not clobber it
  /// back to whatever was on disk before that write finished - the same
  /// generation guard `personal_space_visibility.dart`'s own controller
  /// carries for the identical shape of race.
  int _generation = 0;

  /// Resolves once the persisted state, if any, has been read. Exposed so a
  /// caller modelling a relaunch - this controller is rebuilt fresh every
  /// time the canvas pane reopens - can wait for exactly that, rather than
  /// guessing how many event-loop turns a `SharedPreferences` round trip
  /// takes.
  late final Future<void> ready;

  Future<void> _load() async {
    final generation = _generation;
    try {
      final prefs = await _ref.read(preferencesProvider.future);
      if (!mounted || generation != _generation) return;
      final storedCorner = prefs.getString(canvasSelfBubbleCornerKey);
      state = CanvasSelfPresenceState(
        hidden: prefs.getBool(canvasSelfBubbleHiddenKey) ?? false,
        corner: CanvasSelfBubbleCorner.values.firstWhere(
          (corner) => corner.name == storedCorner,
          orElse: () => CanvasSelfBubbleCorner.bottomRight,
        ),
      );
    } catch (_) {
      // A prefs store that cannot be read leaves the bubble at its default: visible, bottom-right.
    }
  }

  /// Hides the bubble; reversed by calling this again with `false`, which is
  /// exactly what the canvas overflow menu's own toggle item does - there is
  /// no separate "show" method to keep in step with it.
  Future<void> setHidden(bool hidden) async {
    _generation++;
    state = state.copyWith(hidden: hidden);
    try {
      final prefs = await _ref.read(preferencesProvider.future);
      await prefs.setBool(canvasSelfBubbleHiddenKey, hidden);
    } catch (_) {
      // Best effort: a write failure must not stop this session's toggle from taking effect.
    }
  }

  /// Where a drag settled - called by `CanvasSelfPresenceOverlay` once per
  /// released drag, never mid-drag, so a write failure costs at most one
  /// forgotten snap rather than one per frame of motion.
  Future<void> setCorner(CanvasSelfBubbleCorner corner) async {
    _generation++;
    state = state.copyWith(corner: corner);
    try {
      final prefs = await _ref.read(preferencesProvider.future);
      await prefs.setString(canvasSelfBubbleCornerKey, corner.name);
    } catch (_) {
      // Best effort, same reasoning as setHidden.
    }
  }
}

/// Deliberately not `autoDispose`: the canvas pane is torn down and rebuilt
/// every time it opens and closes (see `canvas_pane.dart`'s own module doc),
/// and disposing this alongside it would re-run the async load on every
/// reopen, flashing the bubble to its default corner before the stored one
/// loads back in.
final canvasSelfPresenceProvider =
    StateNotifierProvider<
      CanvasSelfPresenceController,
      CanvasSelfPresenceState
    >((ref) => CanvasSelfPresenceController(ref));
