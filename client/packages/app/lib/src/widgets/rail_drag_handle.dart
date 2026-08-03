// SPDX-License-Identifier: Apache-2.0
/// The channel rail's own edge: drag it to collapse or restore the rail.
///
/// Replaces the header's dedicated toggle button (#256): the owner asked for
/// manual collapse without a chrome button, "a small icon to drag to the
/// right and can drag to the left to hide". Reads and writes the same
/// [channelRailVisibleProvider] #256 already shipped, so nothing about how
/// the collapsed state is stored or restored changes, only how it is
/// reached.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import 'channel_rail.dart';

/// How far a horizontal drag has to travel before it flips the provider,
/// wide enough that a stray trackpad wobble while reaching for the divider
/// cannot fire it by accident.
const double _dragThreshold = 40;

/// Sits where the rail meets the conversation, at every width that docks the
/// rail beside it (medium and expanded; the compact drawer from #301 is a
/// separate mechanism and never builds this at all).
///
/// Collapsed, this is the *only* way back: there is no button anywhere else
/// that restores the rail, so it always renders a real, hittable pill with
/// [AppIcons.dragHandle] on it rather than the empty gap a hidden rail would
/// otherwise leave. `rail_drag_handle_test.dart`'s discoverability test
/// mutation-tests exactly this: hiding the pill while collapsed is the one
/// failure mode this feature cannot ship with.
///
/// There is deliberately no pointer `onTap` in [build]: sharing one
/// recognizer between a tap and a horizontal drag means the gesture arena
/// resolves any drag that never clears its own slop as a tap, which would
/// toggle the rail on the same small wobble the drag threshold exists to
/// absorb. Assistive tech and the keyboard get an explicit, separate
/// activation instead, through `Semantics.onTap` and `ActivateIntent` -
/// neither of which a pointer's own tap ever reaches.
class RailDragHandle extends ConsumerStatefulWidget {
  const RailDragHandle({super.key});

  @override
  ConsumerState<RailDragHandle> createState() => _RailDragHandleState();
}

class _RailDragHandleState extends ConsumerState<RailDragHandle> {
  double _dragExtent = 0;
  bool _hovered = false;

  void _toggle() =>
      ref.read(channelRailVisibleProvider.notifier).update((value) => !value);

  void _onDragUpdate(DragUpdateDetails details, bool visible) {
    _dragExtent += details.delta.dx;
    if (visible && _dragExtent <= -_dragThreshold) {
      ref.read(channelRailVisibleProvider.notifier).state = false;
      _dragExtent = 0;
    } else if (!visible && _dragExtent >= _dragThreshold) {
      ref.read(channelRailVisibleProvider.notifier).state = true;
      _dragExtent = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final visible = ref.watch(channelRailVisibleProvider);
    final touch = AppTouchTargets.of(context);
    // The design system's own hit-target steps: AppIconButton's own problem.
    final hitWidth = touch ? AppSizes.rowTouch : AppSizes.rowPointer;

    return Semantics(
      button: true,
      label: visible ? 'Collapse channel list' : 'Expand channel list',
      onTap: _toggle,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.resizeLeftRight,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _toggle(),
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => _onDragUpdate(details, visible),
          onHorizontalDragEnd: (_) => _dragExtent = 0,
          onHorizontalDragCancel: () => _dragExtent = 0,
          child: Container(
            width: hitWidth,
            color: _hovered ? tokens.surfaceRaised : null,
            child: Center(
              child: visible
                  ? VerticalDivider(width: 1, color: tokens.borderSubtle)
                  : _CollapsedGrip(tokens: tokens),
            ),
          ),
        ),
      ),
    );
  }
}

/// The collapsed state's own affordance: a visible pill rather than the
/// blank gap a hidden rail would otherwise leave, so there is always
/// something on screen naming "the rail is here, pull it open".
class _CollapsedGrip extends StatelessWidget {
  const _CollapsedGrip({required this.tokens});

  final AppTokens tokens;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: AppSpacing.s16),
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s8),
    decoration: BoxDecoration(
      color: tokens.surfaceRaised,
      border: Border.all(color: tokens.borderSubtle),
      borderRadius: BorderRadius.circular(AppRadii.control),
    ),
    child: Icon(
      AppIcons.dragHandle,
      size: AppSizes.icon16,
      color: tokens.textSecondary,
    ),
  );
}
