// SPDX-License-Identifier: Apache-2.0
/// A side pane's content arriving with its slot: a fade plus a short drift
/// in from the edge the pane lives on, once, on mount.
///
/// Extracted from the member pane's own entrance in `home_shell.dart` so the
/// channel rail's reveal matches it instead of snapping to full opacity the
/// frame its slot starts widening. The drift direction follows the edge the
/// pane lives on: the rail comes in from the left ([fromLeft] true, content
/// starting 16px left of rest), the member pane from the right. Reduce
/// motion lands at the final state with no travel, via [AppMotion.reduced].
library;

import 'package:flutter/widgets.dart';
import 'package:slimm_design_system/design_system.dart';

class AppPanelReveal extends StatelessWidget {
  const AppPanelReveal({
    required this.fromLeft,
    required this.child,
    super.key,
  });

  final bool fromLeft;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: AppMotion.reduced(context, AppMotion.base),
    curve: AppMotion.entrance,
    builder: (context, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(
        offset: Offset((fromLeft ? -16 : 16) * (1 - t), 0),
        child: child,
      ),
    ),
    child: child,
  );
}
