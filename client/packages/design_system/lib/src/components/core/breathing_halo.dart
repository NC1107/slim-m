// SPDX-License-Identifier: Apache-2.0
/// A soft disc that breathes behind a waiting state's glyph.
///
/// For the screens that are legitimately about waiting - a call connecting,
/// a rejoin prompt - whose glyph otherwise floats in a void with nothing
/// saying the app is alive. It rides the same [AppMotion.speakingPulse]
/// clock the speaking ring does, but bounded: a few breaths on mount, then
/// rest at full strength. A rejoin screen is a resting state somebody may
/// sit on for minutes, and an unbounded loop there is a frame scheduled
/// forever - the exact "a widget that animates whether or not it is doing
/// anything" trap the speaking ring's own doc names, and what would hang
/// every `pumpAndSettle` that crosses one of these screens. Under reduce
/// motion it holds still at full strength from the first frame.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_motion.dart';
import '../../app_tokens.dart';

class AppBreathingHalo extends StatefulWidget {
  const AppBreathingHalo({required this.child, this.size = 64, super.key});

  final Widget child;

  /// The disc's diameter at rest; a breath dips it about 6% under this.
  final double size;

  @override
  State<AppBreathingHalo> createState() => _AppBreathingHaloState();
}

class _AppBreathingHaloState extends State<AppBreathingHalo>
    with SingleTickerProviderStateMixin {
  /// How many times the disc breathes before resting.
  static const int _breaths = 3;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: AppMotion.speakingPulse * (2 * _breaths),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppMotion.isReduced(context)) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating && _pulse.value == 0) {
      _pulse.forward();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// Full at both ends, dipping [_breaths] times in between.
  static double _breath(double t) =>
      0.5 + 0.5 * math.cos(2 * math.pi * _breaths * t);

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return SizedBox(
      width: widget.size * 1.12,
      height: widget.size * 1.12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = _breath(_pulse.value);
              return Transform.scale(
                scale: 0.94 + 0.06 * t,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tokens.accentSoft.withValues(alpha: 0.5 + 0.5 * t),
                    border: Border.all(
                      color: tokens.accentFill.withValues(
                        alpha: 0.25 + 0.35 * t,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          widget.child,
        ],
      ),
    );
  }
}
