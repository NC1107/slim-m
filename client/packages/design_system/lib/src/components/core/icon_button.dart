// SPDX-License-Identifier: Apache-2.0
/// A square, icon-only control: header actions, toolbar buttons, message-row
/// hover actions.
library;

import 'package:flutter/material.dart';

import '../../app_haptics.dart';
import '../../app_metrics.dart';
import '../../app_motion.dart';
import '../../app_tokens.dart';
import '../../touch_targets.dart';

enum AppIconButtonVariant { ghost, outline, danger }

/// Visual diameter. `sm`/`lg`/`touch` land exactly on [AppSizes.controlSm]/
/// [AppSizes.controlMd]/[AppSizes.controlLg] (26/34/38); `md`, the default,
/// is 28, a size the current token set has no step for.
enum AppIconButtonSize { sm, md, lg, touch }

double _diameterFor(AppIconButtonSize size) => switch (size) {
      AppIconButtonSize.sm => AppSizes.controlSm,
      AppIconButtonSize.md => 28,
      AppIconButtonSize.lg => AppSizes.controlMd,
      AppIconButtonSize.touch => AppSizes.controlLg,
    };

/// A square icon-only button with rounded corners, not a circle.
///
/// [active] is a persistent accent-tinted state (a toggled-on control, an
/// applied filter): a fill plus an accent border. It is a different thing
/// from keyboard focus, which is a ring drawn from [AppTokens.focusRing] on
/// top of whatever [active]/[variant] state is already showing. Conflating
/// the two would make a toggled-on button indistinguishable from one a
/// keyboard user merely tabbed onto.
///
/// The visible sizes (26/28/34/38) are all smaller than this system's touch
/// minimum. [touch] (matching [AppListRow]'s parameter of the same name)
/// grows the invisible tap area to [AppSizes.rowTouch] without growing the
/// glyph, the same "small control, bigger tap target" split the row height
/// already uses. Left unset it follows [AppTouchTargets.of].
class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.variant = AppIconButtonVariant.ghost,
    this.size = AppIconButtonSize.md,
    this.active = false,
    this.touch,
    this.iconSize = AppSizes.icon20,
    this.tooltip,
    this.focusNode,
  });

  final IconData icon;

  /// Announced by assistive tech. Required: an icon-only control with
  /// nothing to say its own name is unreachable to a screen reader.
  final String semanticLabel;

  final VoidCallback? onPressed;
  final AppIconButtonVariant variant;
  final AppIconButtonSize size;
  final bool active;

  /// Null means "whatever this subtree is at", read from [AppTouchTargets].
  final bool? touch;
  final double iconSize;
  final String? tooltip;
  final FocusNode? focusNode;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hovered = false;
  bool _focused = false;

  /// Finger-down feedback for a phone, where there is no hover fill to lean
  /// on; a small scale-down that a haptic tick lands alongside.
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final enabled = widget.onPressed != null;
    final visualSize = _diameterFor(widget.size);
    final radius =
        visualSize >= AppSizes.controlMd ? AppRadii.card : AppRadii.control;
    final touch = widget.touch ?? AppTouchTargets.of(context);
    final hitTarget = touch ? AppSizes.rowTouch : AppSizes.rowPointer;
    final outerSize = visualSize > hitTarget ? visualSize : hitTarget;

    Color ink;
    Color fill;
    Color? border;

    switch (widget.variant) {
      case AppIconButtonVariant.ghost:
        ink = tokens.textSecondary;
        fill = Colors.transparent;
        border = null;
      case AppIconButtonVariant.outline:
        ink = tokens.textSecondary;
        fill = Colors.transparent;
        border = tokens.borderSubtle;
      case AppIconButtonVariant.danger:
        ink = tokens.dangerText;
        fill = Colors.transparent;
        border = tokens.dangerBorder;
    }

    if (_hovered && enabled && !widget.active) {
      fill = tokens.surfaceRaised;
    }

    if (widget.active) {
      fill = tokens.accentSoft;
      ink = tokens.accent;
      border = tokens.accentFill;
    }

    final button = Container(
      width: visualSize,
      height: visualSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(radius),
        border: border != null ? Border.all(color: border) : null,
      ),
      foregroundDecoration: _focused
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: tokens.focusRing, width: 2),
            )
          : null,
      child: Icon(widget.icon, size: widget.iconSize, color: ink),
    );

    Widget control = Semantics(
      label: widget.semanticLabel,
      button: true,
      enabled: enabled,
      toggled: widget.active,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: FocusableActionDetector(
          enabled: enabled,
          focusNode: widget.focusNode,
          mouseCursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
          onShowHoverHighlight: (v) => setState(() => _hovered = v),
          onShowFocusHighlight: (v) => setState(() => _focused = v),
          actions: !enabled
              ? const <Type, Action<Intent>>{}
              : <Type, Action<Intent>>{
                  ActivateIntent: CallbackAction<ActivateIntent>(
                      onInvoke: (_) => widget.onPressed!()),
                },
          child: GestureDetector(
            onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
            onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
            onTapCancel:
                enabled ? () => setState(() => _pressed = false) : null,
            onTap: enabled
                ? () {
                    AppHaptics.selection();
                    widget.onPressed!();
                  }
                : null,
            child: SizedBox(
              width: outerSize,
              height: outerSize,
              child: Center(
                child: AnimatedScale(
                  scale: _pressed ? AppMotion.pressScale : 1,
                  duration: AppMotion.reduced(context, AppMotion.fast),
                  curve: AppMotion.entrance,
                  child: button,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      control = Tooltip(message: widget.tooltip!, child: control);
    }

    return control;
  }
}
