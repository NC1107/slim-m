// SPDX-License-Identifier: Apache-2.0
/// The way back to the newest message once a reader has scrolled into
/// history, since the read marker only follows the view there and scrolling
/// up should never look like giving up the thread.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

/// Always mounted so its fade has something to reverse against; renders as
/// nothing once the transition settles at [visible] false.
class JumpToLatestButton extends StatelessWidget {
  const JumpToLatestButton({
    super.key,
    required this.visible,
    required this.onTap,
  });

  final bool visible;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.reduced(context, AppMotion.base),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: !visible
          ? const SizedBox.shrink(key: ValueKey('jump-to-latest-hidden'))
          : Padding(
              key: const ValueKey('jump-to-latest-visible'),
              padding: const EdgeInsets.only(bottom: AppSpacing.s12),
              child: AppButton(
                label: 'Jump to latest',
                icon: AppIcons.chevronDown,
                variant: AppButtonVariant.soft,
                size: AppButtonSize.sm,
                onPressed: onTap,
              ),
            ),
    );
  }
}
