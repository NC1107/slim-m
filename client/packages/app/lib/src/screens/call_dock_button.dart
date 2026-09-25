// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The reusable chip every in-call control draws, split out of
/// `voice_call_controls.dart` to keep that file under the review budget once
/// the keyboard-shortcuts and speaker-switch additions pushed it over.
///
/// Public since before this split: `voice_call_dock.dart`'s canvas toggle and
/// `incoming_call_overlay.dart`'s ring/decline pair already draw the
/// identical chip, not only `CallControls`'s own row.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

class CallDockButton extends StatelessWidget {
  const CallDockButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onPressed,
    this.destructive = false,
    this.pending = false,
    this.onLongPress,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final bool destructive;

  /// Asked for, not in effect yet. Reads as busy rather than on.
  ///
  /// On iOS a screen share is a request the user answers in a system picker,
  /// and nothing is published until they do. Drawing that as active describes
  /// a share nobody can see.
  final bool pending;
  final VoidCallback onPressed;

  /// A secondary action reached by a long press or a right-click, leaving
  /// [onPressed] itself untouched - the share button's own "change source"
  /// needs exactly this, without disturbing the tap-to-stop behaviour
  /// `scripts/lib/e2e_voice.py` already drives by that same tooltip. Null
  /// (every other caller) offers no secondary action at all.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    // Danger is outlined, never filled: unmistakable without being the brightest thing on screen.
    final background = destructive
        ? Colors.transparent
        : active
        ? tokens.accentSoft
        : tokens.surfaceRaised;
    final foreground = destructive
        ? tokens.dangerText
        : active
        ? tokens.accent
        : tokens.textSecondary;
    final border = destructive ? tokens.dangerBorder : tokens.borderSubtle;

    // AppIconButton's own split: a fixed chip, invisible tap area growing to AppSizes.rowTouch at touch density.
    final touch = AppTouchTargets.of(context);
    final hitTarget = touch ? AppSizes.rowTouch : AppSizes.rowPointer;
    const visualSize = AppSizes.controlMd;
    final outerSize = visualSize > hitTarget ? visualSize : hitTarget;

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: AppFocusRing(
          radius: AppRadii.control,
          builder: (context, onFocusChange) => InkWell(
            onTap: onPressed,
            onLongPress: onLongPress,
            onSecondaryTap: onLongPress,
            // AppFocusRing replaces this overlay; see its own doc comment.
            focusColor: Colors.transparent,
            onFocusChange: onFocusChange,
            borderRadius: BorderRadius.circular(AppRadii.control),
            child: SizedBox(
              width: outerSize,
              height: outerSize,
              child: Center(
                child: Container(
                  width: visualSize,
                  height: visualSize,
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(AppRadii.control),
                    border: Border.all(color: border),
                  ),
                  child: pending
                      ? Center(
                          child: SizedBox(
                            width: AppSizes.icon16,
                            height: AppSizes.icon16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: tokens.textSecondary,
                            ),
                          ),
                        )
                      : Icon(icon, size: AppSizes.icon16, color: foreground),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
