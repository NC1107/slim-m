// SPDX-License-Identifier: Apache-2.0
/// The one floating card shape a call's controls and a canvas's controls
/// both sit inside, so "the voice bar" and "the canvas toolbar" read as one
/// idea rather than two competing bars.
///
/// [AppRadii.window] and [AppShadows.float]: both tokens already existed and
/// both were already reserved, by their own doc comments, for exactly this -
/// a floating canvas window and a menu or a dragged object. A control
/// surface that floats over live content rather than reserving a permanent
/// strip at the edge of the screen is the same kind of thing, so it draws
/// from the same two tokens rather than inventing a third shadow the design
/// language's own motion doc explicitly rules out.
///
/// **A right-click anywhere on this card is absorbed and does nothing**,
/// the identical no-op `onSecondaryTapUp` `canvas_self_presence_overlay.dart`
/// already uses for the same reason: this card's own padding, its
/// inter-row divider, and any slack the tool strip's scroll viewport leaves
/// past its five buttons are all real background this card paints over
/// content, not buttons - and a right-click landing there would otherwise
/// hit-test straight through to whatever canvas object sits underneath,
/// opening a menu for content the card is visually hiding. Left-button
/// gestures are deliberately untouched: `TapGestureRecognizer
/// .isPointerAllowed` (the same guarantee `CanvasObjectContextMenu`'s own
/// doc already cites) refuses a primary pointer the moment no primary
/// callback is set, so this can never delay or compete with an ordinary
/// draw, pan or erase on the surface beneath - which is also why a bare
/// primary tap on this card's own background is left as a known, narrower
/// residual rather than fought over: closing it would mean competing with
/// the canvas's own pan recognizer for the same pointer, a real regression
/// risk for no more than a few dp of padding.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// A floating, rounded, shadowed card holding one or more rows of controls,
/// each row separated by a hairline divider.
///
/// Never full-bleed: the caller positions this with margin on every side (see
/// `canvas_call_dock.dart` and `voice_screen.dart`'s own placement), which is
/// what makes it read as floating over content rather than as a bar the
/// content stops above. [rows] is a list rather than one child because a
/// call's controls and a canvas's controls are drawn as genuinely separate
/// rows at touch width - see `CanvasCallDock`'s own doc for why - and a
/// single [Column] here keeps the divider between them in one place instead
/// of every caller redrawing it.
class FloatingDockCard extends StatelessWidget {
  const FloatingDockCard({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final divided = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      if (i > 0) {
        divided.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
            child: Divider(height: 1, thickness: 1, color: tokens.borderSubtle),
          ),
        );
      }
      divided.add(rows[i]);
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // A no-op, not an omission: see this file's own library doc for why a right-click here must never reach a canvas object menu beneath.
      onSecondaryTapUp: (_) {},
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s12,
          vertical: AppSpacing.s8,
        ),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadii.window),
          border: Border.all(color: tokens.borderSubtle),
          boxShadow: AppShadows.float,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: divided),
      ),
    );
  }
}
