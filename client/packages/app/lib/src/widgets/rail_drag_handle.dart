// SPDX-License-Identifier: Apache-2.0
/// The channel rail's own edge: click it to collapse or restore the rail.
///
/// Replaced the header's dedicated toggle button once (#256), then replaced
/// drag-to-resize with a plain click (backlog item 54): the owner found the
/// draggable divider's wide hit region read as "a huge resize bar" for a
/// feature that only ever needed to flip a bit, and said he would settle for
/// a toggle. Reads and writes the same [channelRailVisibleProvider] #256
/// already shipped, so nothing about how the collapsed state is stored or
/// restored changes, only how it is reached.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import 'channel_rail.dart';

/// Sits where the rail meets the conversation, at every width that docks the
/// rail beside it (medium and expanded; the compact drawer from #301 is a
/// separate mechanism and never builds this at all).
///
/// The painted line is always a single hairline - [AppTokens.borderSubtle],
/// tinted with [AppTokens.accentFill] on hover for feedback - never a filled
/// bar, which is the visual half of item 54's fix. The clickable region
/// around it is wider than the line itself purely for hit-testing (the same
/// [AppSizes.rowPointer]/[AppSizes.rowTouch] step every other control uses),
/// a mouse-only affordance since the compact drawer covers touch instead.
///
/// That wide region used to sit uncoloured, which read as a gap rather than
/// a seam: the rail is [AppTokens.surfaceSunken] and the conversation is
/// [AppTokens.surfaceBase], a deliberate step so the panes do not bleed into
/// each other (see the token's own doc), and a neutral strip between the two
/// belonged to neither. Each side of the line is filled to match the surface
/// it actually borders now, so the reserved width disappears into its
/// neighbours and only the hairline itself remains visible.
///
/// Collapsed, this is the *only* way back: there is no button anywhere else
/// that restores the rail, so it always renders a real, hittable
/// [AppIcons.sidebar] glyph rather than the empty gap a hidden rail would
/// otherwise leave. `rail_drag_handle_test.dart`'s discoverability test
/// mutation-tests exactly this: hiding the glyph while collapsed is the one
/// failure mode this feature cannot ship with.
///
/// [GestureDetector] carries `excludeFromSemantics: true`: a real pointer
/// tap needs its own recognizer now that a plain click has to work (it did
/// not before item 54, when only a drag was handled here), but letting it
/// also publish its own tap action bled this control's label onto an
/// unrelated ancestor's - found by dumping the real semantics tree, not by
/// reading the widget, since nothing about the code looked wrong.
class RailDragHandle extends ConsumerStatefulWidget {
  const RailDragHandle({super.key});

  @override
  ConsumerState<RailDragHandle> createState() => _RailDragHandleState();
}

class _RailDragHandleState extends ConsumerState<RailDragHandle> {
  bool _hovered = false;

  void _toggle() =>
      ref.read(channelRailVisibleProvider.notifier).update((value) => !value);

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final visible = ref.watch(channelRailVisibleProvider);
    final touch = AppTouchTargets.of(context);
    final hitWidth = touch ? AppSizes.rowTouch : AppSizes.rowPointer;
    final lineColor = _hovered ? tokens.accentFill : tokens.borderSubtle;

    return Semantics(
      button: true,
      label: visible ? 'Collapse channel list' : 'Expand channel list',
      onTap: _toggle,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _toggle(),
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // The real pointer tap; the outer Semantics covers accessibility, see its own doc.
          excludeFromSemantics: true,
          onTap: _toggle,
          child: SizedBox(
            width: hitWidth,
            child: visible
                ? Row(
                    children: [
                      Expanded(child: Container(color: tokens.surfaceSunken)),
                      VerticalDivider(width: 1, color: lineColor),
                      Expanded(child: Container(color: tokens.surfaceBase)),
                    ],
                  )
                : Center(
                    child: Icon(
                      AppIcons.sidebar,
                      size: AppSizes.icon16,
                      color: lineColor,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
