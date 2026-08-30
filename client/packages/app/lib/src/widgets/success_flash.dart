// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A transient "Saved" acknowledgement for a write that succeeded quietly.
///
/// `runGuarded` gave failure a durable shape (`AppErrorState`) and left
/// success silent, so a toggle or a rename that worked gave nothing back.
/// Feed this `GuardedActionState.successTick`: each bump plays one short
/// check-and-caption flash - fade in, hold, fade out - driven by a single
/// controller with no timer, so a test that triggers one settles cleanly.
/// The band it sits in grows and collapses through `AppRevealBand`, the
/// same in-place reveal the composer's own banners use.
///
/// Under reduce motion the cue still appears and disappears, sharply, on
/// the same clock: a timed acknowledgement is information rather than
/// decoration, so it is never suppressed outright - the same reasoning
/// `app_motion.dart` already records for busy spinners.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

class SuccessFlash extends StatefulWidget {
  const SuccessFlash({required this.tick, this.label = 'Saved', super.key});

  /// Plays one flash every time this changes to a non-zero value.
  final int tick;

  /// What the cue says, visibly and to a screen reader alike.
  final String label;

  @override
  State<SuccessFlash> createState() => _SuccessFlashState();
}

class _SuccessFlashState extends State<SuccessFlash>
    with SingleTickerProviderStateMixin {
  /// Fade in over the first 12%, hold, fade out over the last 24%.
  static const _lifetime = Duration(milliseconds: 1400);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _lifetime,
  );

  @override
  void didUpdateWidget(SuccessFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tick != oldWidget.tick && widget.tick > 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _opacityAt(double t, {required bool reduced}) {
    if (reduced) return 1;
    if (t < 0.12) return t / 0.12;
    if (t > 0.76) return (1 - t) / 0.24;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => AppRevealBand(
        child: _controller.isAnimating
            ? Opacity(
                opacity: _opacityAt(
                  _controller.value,
                  reduced: AppMotion.isReduced(context),
                ),
                child: child,
              )
            : null,
      ),
      child: Semantics(
        liveRegion: true,
        label: widget.label,
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpacing.s8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(AppIcons.check, size: AppSizes.icon16, color: tokens.accent),
              const SizedBox(width: AppSpacing.s8),
              ExcludeSemantics(
                child: Text(
                  widget.label,
                  style: AppText.caption.copyWith(color: tokens.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
