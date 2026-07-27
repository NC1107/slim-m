// SPDX-License-Identifier: Apache-2.0
/// The text button: the one control every screen with a real action reaches
/// for.
///
/// Five variants carry a deliberate hierarchy through weight as well as
/// colour: [AppButtonVariant.primary] is filled and semi-bold on purpose, and
/// the rule that matters is the source design's own: *the only filled button
/// on a screen should be the one real action*. Reaching for a second
/// [AppButtonVariant.primary] to make a secondary action "stand out more" is
/// exactly the mistake this hierarchy exists to prevent; [AppButtonVariant.soft]
/// is the tier for "important but not the one action."
library;

import 'package:flutter/material.dart';

import '../../app_metrics.dart';
import '../../app_tokens.dart';
import '../../app_typography.dart';
import '../../touch_targets.dart';

enum AppButtonVariant { primary, secondary, ghost, soft, danger }

/// `sm`/`lg` (28/40) have no matching [AppSizes] step; `md` lands exactly on
/// [AppSizes.controlMd] (34).
enum AppButtonSize { sm, md, lg }

class _Metrics {
  const _Metrics(
      {required this.height,
      required this.horizontalPadding,
      required this.textStyle});
  final double height;
  final double horizontalPadding;
  final TextStyle textStyle;
}

_Metrics _metricsFor(AppButtonSize size) => switch (size) {
      AppButtonSize.sm => const _Metrics(
          height: 28,
          horizontalPadding: AppSpacing.s12,
          textStyle: AppText.caption,
        ),
      AppButtonSize.md => const _Metrics(
          height: AppSizes.controlMd,
          horizontalPadding: AppSpacing.s16,
          textStyle: AppText.ui,
        ),
      AppButtonSize.lg => const _Metrics(
          height: 40, horizontalPadding: AppSpacing.s20, textStyle: AppText.ui),
    };

class _Look {
  const _Look(
      {required this.background,
      required this.foreground,
      required this.border,
      required this.weight});
  final Color background;
  final Color foreground;
  final Color border;
  final FontWeight weight;
}

_Look _lookFor(AppButtonVariant variant, AppTokens tokens) => switch (variant) {
      AppButtonVariant.primary => _Look(
          background: tokens.accentFill,
          foreground: tokens.accentOn,
          border: tokens.accentFill,
          weight: AppWeights.semi,
        ),
      AppButtonVariant.secondary => _Look(
          background: Colors.transparent,
          foreground: tokens.textPrimary,
          border: tokens.borderSubtle,
          weight: AppWeights.medium,
        ),
      AppButtonVariant.ghost => _Look(
          background: Colors.transparent,
          foreground: tokens.textSecondary,
          border: Colors.transparent,
          weight: AppWeights.regular,
        ),
      AppButtonVariant.soft => _Look(
          background: tokens.accentSoft,
          foreground: tokens.accent,
          border: tokens.accentFill,
          weight: AppWeights.medium,
        ),
      AppButtonVariant.danger => _Look(
          background: Colors.transparent,
          foreground: tokens.dangerText,
          border: tokens.dangerBorder,
          weight: AppWeights.medium,
        ),
    };

/// A labelled, tappable control with an optional leading icon.
///
/// [touch] (matching [AppListRow]'s parameter of the same name) grows the
/// button itself, not an invisible tap box around it, to meet
/// [AppSizes.rowTouch]: unlike [AppIconButton], a text button's whole body is
/// already visible content, so the touch floor should change what is drawn
/// rather than pad around it. Left unset it follows [AppTouchTargets.of].
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.secondary,
    this.size = AppButtonSize.md,
    this.icon,
    this.full = false,
    this.disabled = false,
    this.touch,
    this.semanticLabel,
    this.focusNode,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final IconData? icon;

  /// Fills the width the parent gives it, for a form's or a sheet's one
  /// full-width action.
  final bool full;

  /// Independent of [onPressed], matching the source design: a button keeps
  /// its real handler (a save action a caller re-enables once a form becomes
  /// valid, say) rather than having to null it out and reattach it later.
  final bool disabled;

  /// Null means "whatever this subtree is at", read from [AppTouchTargets].
  final bool? touch;
  final String? semanticLabel;
  final FocusNode? focusNode;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final enabled = !widget.disabled && widget.onPressed != null;
    final metrics = _metricsFor(widget.size);
    final look = _lookFor(widget.variant, tokens);
    final touch = widget.touch ?? AppTouchTargets.of(context);
    final hitTarget = touch ? AppSizes.rowTouch : AppSizes.rowPointer;
    final height = metrics.height > hitTarget ? metrics.height : hitTarget;

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: AppSizes.icon16, color: look.foreground),
          const SizedBox(width: AppSpacing.s8),
        ],
        // Flexible so a long label at a large text scale ellipsizes instead of
        // overflowing; with room to spare the intrinsic width is unchanged.
        Flexible(
          child: Text(
            widget.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: metrics.textStyle.copyWith(
                color: look.foreground, fontWeight: look.weight, height: 1),
          ),
        ),
      ],
    );

    final button = Container(
      height: height,
      width: widget.full ? double.infinity : null,
      padding: EdgeInsets.symmetric(horizontal: metrics.horizontalPadding),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: look.background,
        border: Border.all(color: look.border),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      foregroundDecoration: _focused
          ? BoxDecoration(
              border: Border.all(color: tokens.focusRing, width: 2),
              borderRadius: BorderRadius.circular(AppRadii.control),
            )
          : null,
      // The label and icon are purely visual here: without this, the Text's
      // own auto-generated semantics merges with the explicit label below
      // into a single doubled announcement ("Save\nSave").
      child: ExcludeSemantics(child: content),
    );

    final control = Semantics(
      label: widget.semanticLabel ?? widget.label,
      button: true,
      enabled: enabled,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: FocusableActionDetector(
          enabled: enabled,
          focusNode: widget.focusNode,
          mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          actions: !enabled
              ? const <Type, Action<Intent>>{}
              : <Type, Action<Intent>>{
                  ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (_) => widget.onPressed!()),
                },
          child: GestureDetector(
              onTap: enabled ? widget.onPressed : null, child: button),
        ),
      ),
    );

    return widget.full ? control : IntrinsicWidth(child: control);
  }
}
