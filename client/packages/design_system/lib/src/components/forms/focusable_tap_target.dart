// SPDX-License-Identifier: Apache-2.0
/// A focusable, tappable control shared by the form widgets in this
/// directory.
///
/// Every one of them needs the same three things: a focus node it can own or
/// receive, keyboard activation on Enter and Space, and a focus ring drawn
/// from `tokens.focusRing` that sits just outside the control rather than
/// reusing the accent border a selected or active state already draws.
/// Building that once here is what keeps several sibling widgets from
/// drifting into slightly different versions of the same behaviour.
///
/// The ring hugs the visible control tightly; the hit-target floor grows the
/// invisible tappable margin around it instead, so a small chip on a touch
/// layout gets a bigger tap area without a ring that floats away from what it is
/// meant to outline.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_metrics.dart';
import '../../app_tokens.dart';

/// The gap between a control's edge and its focus ring, and the ring's own
/// stroke width. There is no dedicated token for either: both are reserved
/// space kept constant whether or not the ring is drawn, so gaining focus
/// never shifts layout.
const double focusRingGap = 2;
const double focusRingWidth = 2;

/// The width below which rows compact to touch sizing, mirroring the layout
/// class breakpoint the app shell uses for its panes. Mirrored here rather
/// than imported so this package does not depend on the app shell package;
/// a form control and the row it sits in still agree on what "the touch
/// size" is, because both read the same width.
double minHitExtent(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 600
        ? AppSizes.rowTouch
        : AppSizes.rowPointer;

typedef FocusableTapBuilder = Widget Function(
  BuildContext context,
  bool focused,
  bool hovered,
);

class FocusableTapTarget extends StatefulWidget {
  const FocusableTapTarget({
    super.key,
    required this.builder,
    this.onTap,
    this.focusNode,
    this.semanticLabel,
    this.enabled = true,
    this.isButton = true,
    this.selected,
    this.toggled,
    this.ringRadius = AppRadii.control,
  });

  final FocusableTapBuilder builder;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final String? semanticLabel;
  final bool enabled;
  final bool isButton;
  final bool? selected;
  final bool? toggled;
  final double ringRadius;

  @override
  State<FocusableTapTarget> createState() => _FocusableTapTargetState();
}

class _FocusableTapTargetState extends State<FocusableTapTarget> {
  late final FocusNode _focusNode;
  bool _ownsFocusNode = false;
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode = widget.focusNode ?? FocusNode();
  }

  @override
  void dispose() {
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _activate() {
    if (widget.enabled) widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final content = widget.builder(context, _focused, _hovered);

    // The ring hugs the control tightly; the hit-target floor below grows the
    // invisible margin instead. See the library doc at the top of the file.
    final ring = Container(
      padding: const EdgeInsets.all(focusRingGap),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.ringRadius + focusRingGap),
        border: Border.all(
          color: _focused ? tokens.focusRing : Colors.transparent,
          width: focusRingWidth,
        ),
      ),
      child: content,
    );

    final hitExtent = minHitExtent(context);

    return Semantics(
      button: widget.isButton,
      enabled: widget.enabled,
      label: widget.semanticLabel,
      selected: widget.selected,
      toggled: widget.toggled,
      onTap: widget.enabled ? _activate : null,
      child: Focus(
        focusNode: _focusNode,
        canRequestFocus: widget.enabled,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.enter ||
              key == LogicalKeyboardKey.space) {
            _activate();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: widget.enabled
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.enabled
                ? () {
                    _focusNode.requestFocus();
                    _activate();
                  }
                : null,
            child: Container(
              constraints:
                  BoxConstraints(minWidth: hitExtent, minHeight: hitExtent),
              alignment: Alignment.center,
              child: ring,
            ),
          ),
        ),
      ),
    );
  }
}
