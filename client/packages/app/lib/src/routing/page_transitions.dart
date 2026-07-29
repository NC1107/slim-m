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

/// A page that cross-fades and rises a hair into place, collapsing to an
/// instant swap under reduce-motion.
///
/// [key] is what makes a channel switch animate at all: each destination is a
/// distinct page under its own key, so the framework fades the old one out and
/// the new one in rather than reusing a single page and rebuilding in place.
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
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: AppMotion.entrance,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.02),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
    child: child,
  );
}
