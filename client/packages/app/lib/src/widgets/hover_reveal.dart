// SPDX-License-Identifier: Apache-2.0
/// The hover-reveal mechanism a message row uses to show its add-reaction
/// button only on hover, and that the emoji picker and the context menu
/// reuse to stay mounted while their own popup is open.
///
/// Split out of `message_row.dart`, which is where both of those other
/// files were reaching in for [HoverRevealScope] before this existed.
library;

import 'package:flutter/material.dart';

/// Tracks pointer hover for one subtree.
///
/// Its own widget so a caller like `MessageRow` can stay stateless: a row
/// has a dozen fields, and converting it wholesale to carry one bool would
/// touch every reference in that file.
class HoverReveal extends StatefulWidget {
  const HoverReveal({super.key, required this.builder});

  final Widget Function(BuildContext context, bool hovered) builder;

  @override
  State<HoverReveal> createState() => _HoverRevealState();
}

class _HoverRevealState extends State<HoverReveal> {
  bool _hovered = false;
  bool _pinned = false;

  void _pin(bool pinned) {
    if (_pinned != pinned) setState(() => _pinned = pinned);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: HoverRevealScope(
        pin: _pin,
        child: widget.builder(context, _hovered || _pinned),
      ),
    );
  }
}

/// Lets a hover-revealed control keep itself mounted while it has a popup open.
///
/// Without it, moving the pointer onto the popup leaves the row's [MouseRegion],
/// which unmounts the control and the popup with it - so the thing can be opened
/// and never clicked.
class HoverRevealScope extends InheritedWidget {
  const HoverRevealScope({super.key, required this.pin, required super.child});

  final ValueChanged<bool> pin;

  /// Null outside a hover-revealed subtree, where nothing needs pinning.
  static HoverRevealScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HoverRevealScope>();

  @override
  bool updateShouldNotify(HoverRevealScope oldWidget) => pin != oldWidget.pin;
}
