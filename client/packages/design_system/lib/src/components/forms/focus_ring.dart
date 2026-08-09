// SPDX-License-Identifier: Apache-2.0
/// A focus ring for a child that already owns its own focusability and
/// gestures - typically a bare `InkWell` whose own intrinsic layout (an
/// `Expanded` descendant, say) or non-square shape rules out
/// [FocusableTapTarget], which imposes both a hit-target floor and a
/// shrink-to-content sizing that widget cannot give up.
///
/// The gap and stroke mirror [FocusableTapTarget]'s own ring exactly
/// ([focusRingGap], [focusRingWidth]): reserved whether or not the ring is
/// drawn, so gaining focus never shifts layout, and hugging the wrapped
/// control tightly rather than floating away from what it outlines.
library;

import 'package:flutter/material.dart';

import '../../app_tokens.dart';
import 'focusable_tap_target.dart';

class AppFocusRing extends StatefulWidget {
  const AppFocusRing({super.key, required this.builder, required this.radius});

  /// Builds the interactive content. Wire an interactive descendant's own
  /// focus-change signal straight into the handed callback (`InkWell.
  /// onFocusChange` fits directly) and set that descendant's own
  /// `focusColor` to transparent, or the Material default overlay and this
  /// ring draw at once.
  final Widget Function(
    BuildContext context,
    ValueChanged<bool> onFocusChange,
  ) builder;

  /// The corner radius of the wrapped control itself; the ring's own radius
  /// is derived by adding [focusRingGap], matching [FocusableTapTarget].
  final double radius;

  @override
  State<AppFocusRing> createState() => _AppFocusRingState();
}

class _AppFocusRingState extends State<AppFocusRing> {
  bool _focused = false;

  void _onFocusChange(bool focused) {
    if (focused != _focused) setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      padding: const EdgeInsets.all(focusRingGap),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius + focusRingGap),
        border: Border.all(
          color: _focused ? tokens.focusRing : Colors.transparent,
          width: focusRingWidth,
        ),
      ),
      child: widget.builder(context, _onFocusChange),
    );
  }
}
