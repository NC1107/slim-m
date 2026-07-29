// SPDX-License-Identifier: Apache-2.0
/// How a settings or administration screen is presented.
///
/// On a phone it is the whole window, because a phone has room for one thing
/// at a time and taking it over is the point. On a desktop window it floats
/// over the app instead: the rail and the conversation stay where they were,
/// the panel is only as big as it needs to be, and clicking beside it or
/// pressing Escape puts it away. A screen that swallows a monitor to show
/// eight rows is the phone layout wearing a desktop's clothes.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';

/// How large the floating panel is allowed to get.
///
/// Tall rather than square: these are lists, and a short wide panel wastes the
/// height a monitor has most of.
const double kModalMaxWidth = 860;
const double kModalMaxHeight = 720;

/// The page for a route that is a screen on a phone and a modal on a desktop.
///
/// [child] is the screen itself, unchanged: it keeps its own app bar, which
/// becomes the panel's title bar, so neither the screen nor its tests need to
/// know which of the two it is being shown as.
Page<void> modalPage(BuildContext context, Widget child) {
  if (MediaQuery.sizeOf(context).width < kCompactWidth) {
    return AppMotion.isReduced(context)
        ? NoTransitionPage<void>(child: child)
        : MaterialPage<void>(child: child);
  }
  // The motion spec's one 280ms moment: scrim and panel enter together, the
  // panel rising 16px; the exit runs faster (180ms, ease-in) because leaving
  // should always feel quicker than arriving.
  return CustomTransitionPage<void>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: const Color(0x99000000),
    barrierLabel: 'Dismiss',
    transitionDuration: AppMotion.reduced(context, AppMotion.slow),
    reverseTransitionDuration: AppMotion.reduced(context, AppMotion.base),
    transitionsBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.entrance,
        reverseCurve: AppMotion.exit,
      );
      return FadeTransition(
        opacity: curved,
        child: AnimatedBuilder(
          animation: curved,
          builder: (context, child) => Transform.translate(
            offset: Offset(0, (1 - curved.value) * 16),
            child: child,
          ),
          child: child,
        ),
      );
    },
    child: _ModalPanel(child: child),
  );
}

class _ModalPanel extends StatelessWidget {
  const _ModalPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // Nothing underneath means this was opened cold, from a pasted URL rather
    // than from inside the app, and a transparent route would show the void
    // behind it. The app's own background stands in for the shell that would
    // otherwise be there.
    final floating = Navigator.of(context).canPop();
    final size = MediaQuery.sizeOf(context);

    // Floating over the dimmed app, the barrier already separates the panel
    // and a shadow completes it. Opened cold there is no barrier and the
    // ground is the panel's own colour, where a hairline border disappears
    // in light theme and the content read as loose text on a blank window;
    // a sunken backdrop separates the two by contrast instead.
    final panel = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: kModalMaxWidth,
          maxHeight: size.height * 0.86 < kModalMaxHeight
              ? size.height * 0.86
              : kModalMaxHeight,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.card),
            boxShadow: floating ? AppShadows.float : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.card),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.surfaceBase,
                border: Border.all(color: tokens.borderSubtle),
                borderRadius: BorderRadius.circular(AppRadii.card),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );

    if (floating) return panel;
    return ColoredBox(color: tokens.surfaceSunken, child: panel);
  }
}
