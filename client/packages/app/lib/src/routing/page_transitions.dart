// SPDX-License-Identifier: Apache-2.0
/// Route transitions for the shell's own surfaces.
///
/// The settings and administration modals carry their own presentation in
/// `modal_page.dart`. This is the plainer case: one signed-in surface
/// replacing another inside the shell, which used to swap with no transition
/// at all - the "teleport" a real navigation should never read as.
library;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';

import 'breakpoints.dart';

/// A page transition that matches its layout, collapsing to an instant swap
/// under reduce-motion.
///
/// At compact width this is the motion spec's drill-down: the destination
/// slides in full-width while the page beneath parallaxes 30% behind it, so
/// direction says where back goes, and popping reverses exactly. Where both
/// panes are visible there is no drill to express, so the pane cross-fades
/// and rises a hair instead.
///
/// [key] is what makes a channel switch animate at all: each destination is a
/// distinct page under its own key, so the framework animates the old one out
/// and the new one in rather than reusing a single page and rebuilding.
///
/// The wide branch is a genuine fade-through rather than a cross-fade, and
/// that distinction was a real bug: it faded the incoming pane in while the
/// outgoing one sat at full opacity underneath, so for the whole transition
/// two channels were legible at once and read as one drawn over the other.
/// The outgoing pane now clears over the first third before the incoming one
/// begins to arrive.
CustomTransitionPage<void> fadeThroughPage(
  BuildContext context,
  Widget child, {
  required LocalKey key,
}) {
  final duration = AppMotion.reduced(context, AppMotion.base);
  return CustomTransitionPage<void>(
    key: key,
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    transitionsBuilder: _fadeThroughTransition,
    child: child,
  );
}

/// A route pushed imperatively (`Navigator.push`) rather than through
/// go_router, presented with the same drill-down / fade-through language as
/// [fadeThroughPage]. The onboarding server-identity steps are the one place
/// that happens: a route pushed over another should behave the same way
/// everywhere, whichever API put it there.
PageRouteBuilder<T> fadeThroughRoute<T>(
  BuildContext context,
  WidgetBuilder builder,
) {
  final duration = AppMotion.reduced(context, AppMotion.base);
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: _fadeThroughTransition,
  );
}

Widget _fadeThroughTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: AppMotion.entrance,
    reverseCurve: AppMotion.exit,
  );
  if (LayoutClass.of(context) == LayoutClass.compact) {
    final curvedOut = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppMotion.entrance,
      reverseCurve: AppMotion.exit,
    );
    return SlideTransition(
      // This page's own entrance: in from the right edge.
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(curved),
      child: SlideTransition(
        // And its underlay role: 30% left while the next page covers it.
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.3, 0),
        ).animate(curvedOut),
        child: child,
      ),
    );
  }
  // A fade-through, not a cross-fade: see fadeThroughPage's own doc.
  final incoming = CurvedAnimation(
    parent: animation,
    curve: const Interval(0.35, 1, curve: Curves.easeOut),
  );
  final outgoing = CurvedAnimation(
    parent: secondaryAnimation,
    curve: const Interval(0, 0.35, curve: Curves.easeIn),
  );
  return FadeTransition(
    // Its underlay role: gone before whatever replaces it becomes legible.
    opacity: Tween<double>(begin: 1, end: 0).animate(outgoing),
    child: FadeTransition(
      opacity: incoming,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.02),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    ),
  );
}
