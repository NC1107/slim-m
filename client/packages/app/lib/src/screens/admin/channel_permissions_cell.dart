// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// One tri-state cell of the permissions grid. State is carried by fill and
/// glyph together (solid accent check, tinted danger cross, plain outlined
/// arrow), all from existing accent and danger roles, so it never rests on
/// colour alone.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

enum CellState { allow, inherit, deny }

/// The painted chip, shared by [Cell] and the legend so the two cannot drift.
class CellChip extends StatelessWidget {
  const CellChip({
    super.key,
    required this.state,
    this.disabled = false,
    this.pressed = false,
    this.hovered = false,
    this.width = 36,
    this.height = 30,
  });

  final CellState state;
  final bool disabled;
  final bool pressed;
  final bool hovered;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final (fill, border, glyph, icon) = switch (state) {
      CellState.allow => (
        tokens.accentFill,
        tokens.accentFill,
        tokens.accentOn,
        AppIcons.check,
      ),
      CellState.deny => (
        tokens.dangerText.withValues(alpha: 0.14),
        tokens.dangerBorder,
        tokens.dangerText,
        AppIcons.dismiss,
      ),
      CellState.inherit when disabled => (
        Colors.transparent,
        tokens.borderSubtle,
        tokens.textDisabled,
        AppIcons.restrictedChannel,
      ),
      CellState.inherit => (
        tokens.surfaceRaised,
        tokens.borderStrong,
        tokens.textSecondary,
        AppIcons.shapeArrow,
      ),
    };
    final lift = pressed
        ? tokens.textPrimary.withValues(alpha: 0.14)
        : hovered
        ? tokens.textPrimary.withValues(alpha: 0.07)
        : Colors.transparent;
    return AnimatedScale(
      scale: pressed ? 0.92 : 1,
      duration: const Duration(milliseconds: 90),
      child: SizedBox(
        width: width,
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border, width: 1.5),
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: lift,
              borderRadius: BorderRadius.circular(AppRadii.card),
            ),
            child: Icon(icon, size: 16, color: glyph),
          ),
        ),
      ),
    );
  }
}

/// A tappable cell that fills whatever slot the grid gives it, so the touch
/// target is the whole column-by-row area rather than just the chip.
class Cell extends StatefulWidget {
  const Cell({
    super.key,
    required this.state,
    required this.disabled,
    required this.onTap,
  });

  final CellState state;
  final bool disabled;
  final VoidCallback onTap;

  @override
  State<Cell> createState() => _CellState();
}

class _CellState extends State<Cell> {
  bool _pressed = false;
  bool _hovered = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: switch (widget.state) {
      CellState.allow => 'Allow',
      CellState.deny => 'Deny',
      CellState.inherit =>
        widget.disabled ? "Inherit; you can't grant this" : 'Inherit from role',
    },
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: Center(
          child: CellChip(
            state: widget.state,
            disabled: widget.disabled,
            pressed: _pressed,
            hovered: _hovered,
          ),
        ),
      ),
    ),
  );
}
