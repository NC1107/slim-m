// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A one-shot entrance: fade in while rising a few pixels, once, when first
/// shown.
///
/// For a panel or a screen's content that would otherwise snap into place the
/// instant its data resolves. It animates on mount only; to replay it for new
/// content (a call view replacing a join preview, say), give it a [Key] that
/// changes with that content. Honours reduce-motion by landing at its final
/// state with no travel.
library;

import 'package:flutter/widgets.dart';

import 'app_motion.dart';

class AppFadeIn extends StatefulWidget {
  const AppFadeIn({
    super.key,
    required this.child,
    this.duration,
    this.offset = 6,
    this.delay = Duration.zero,
  });

  final Widget child;

  /// Defaults to [AppMotion.base]. A larger surface can ask for
  /// [AppMotion.slow], the chrome's ceiling.
  final Duration? duration;

  /// Logical pixels the content rises from. Zero for a pure fade.
  final double offset;

  /// Held invisible before the fade begins, for staggering siblings.
  /// Implemented as an interval inside the one controller rather than a
  /// timer, so nothing is left pending when a test settles. Ignored under
  /// reduce motion, where the content lands settled on frame one.
  final Duration delay;

  @override
  State<AppFadeIn> createState() => _AppFadeInState();
}

class _AppFadeInState extends State<AppFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: (widget.duration ?? AppMotion.base) + widget.delay,
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AppMotion.isReduced(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final total = _controller.duration!.inMicroseconds;
          final start = total == 0 ? 0.0 : widget.delay.inMicroseconds / total;
          final t = Interval(
            start,
            1,
            curve: AppMotion.entrance,
          ).transform(_controller.value);
          return Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(0, (1 - t) * widget.offset),
              child: child,
            ),
          );
        },
      );
}
