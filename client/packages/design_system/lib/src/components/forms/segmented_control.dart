// SPDX-License-Identifier: Apache-2.0
/// A row of 2-4 mutually exclusive options, in two variants.
///
/// `inline` is a sunken trough where the selected segment becomes a raised
/// chip with a hairline and medium weight. Its selection is deliberately
/// not accent-coloured: a raised surface plus a border plus weight already
/// satisfies the not-colour-alone requirement without needing the accent at
/// all. `cards` is the accent one: full-width option cards with a label, an
/// optional mono hint line, and a check glyph when selected. Onboarding
/// uses `cards`.
library;

import 'package:flutter/material.dart';

import '../../app_icons.dart';
import '../../app_metrics.dart';
import '../../app_tokens.dart';
import '../../app_typography.dart';
import 'focusable_tap_target.dart';

class AppSegmentedOption {
  const AppSegmentedOption({
    required this.label,
    this.hint,
    this.disabled = false,
  });

  final String label;

  /// `cards`-only: an optional mono detail line (e.g. a server address).
  final String? hint;

  /// Shown but not choosable, in [AppTokens.textDisabled] and wiring no tap
  /// handler at all.
  ///
  /// Not the same as a caller dropping the callback: that leaves the option
  /// looking available and reports it as a button to assistive tech, so the
  /// only feedback for an unavailable choice is that nothing happens.
  final bool disabled;
}

enum _Variant { inline, cards }

class AppSegmentedControl extends StatelessWidget {
  const AppSegmentedControl.inline({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSegmentSelected,
    this.semanticLabel,
  })  : _variant = _Variant.inline,
        assert(options.length >= 2,
            'a segmented control needs at least two options');

  const AppSegmentedControl.cards({
    super.key,
    required this.options,
    required this.selectedIndex,
    required this.onSegmentSelected,
    this.semanticLabel,
  })  : _variant = _Variant.cards,
        assert(options.length >= 2,
            'a segmented control needs at least two options');

  final _Variant _variant;
  final List<AppSegmentedOption> options;
  final int selectedIndex;
  final ValueChanged<int> onSegmentSelected;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return switch (_variant) {
      _Variant.inline => _buildInline(context),
      _Variant.cards => _buildCards(context),
    };
  }

  Widget _buildInline(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Semantics(
      label: semanticLabel,
      container: true,
      child: Container(
        // 3px trough padding is the design's own literal; AppSpacing has no
        // step between nothing and s4.
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: tokens.surfaceSunken,
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < options.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.s4),
              _inlineSegment(context, tokens, i),
            ],
          ],
        ),
      ),
    );
  }

  Widget _inlineSegment(BuildContext context, AppTokens tokens, int index) {
    final option = options[index];
    final selected = index == selectedIndex;

    return FocusableTapTarget(
      onTap: option.disabled ? null : () => onSegmentSelected(index),
      enabled: !option.disabled,
      selected: selected,
      semanticLabel: option.label,
      builder: (context, focused, hovered) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 26,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s12),
          decoration: BoxDecoration(
            color: selected ? tokens.surfaceRaised : Colors.transparent,
            border: Border.all(
                color: selected ? tokens.borderSubtle : Colors.transparent),
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Text(
            option.label,
            textAlign: TextAlign.center,
            style: AppText.caption.copyWith(
              color: switch ((option.disabled, selected)) {
                (true, _) => tokens.textDisabled,
                (false, true) => tokens.textPrimary,
                (false, false) => tokens.textSecondary,
              },
              fontWeight: selected ? AppWeights.medium : AppWeights.regular,
              fontFamily: AppFonts.sans,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCards(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    return Semantics(
      label: semanticLabel,
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.s8),
            Expanded(child: _card(context, tokens, i)),
          ],
        ],
      ),
    );
  }

  Widget _card(BuildContext context, AppTokens tokens, int index) {
    final selected = index == selectedIndex;
    final option = options[index];

    return FocusableTapTarget(
      onTap: () => onSegmentSelected(index),
      selected: selected,
      semanticLabel: option.hint == null
          ? option.label
          : '${option.label}, ${option.hint}',
      builder: (context, focused, hovered) {
        return Container(
          padding: const EdgeInsets.all(AppSpacing.s12),
          decoration: BoxDecoration(
            color: selected ? tokens.accentSoft : Colors.transparent,
            border: Border.all(
                color: selected ? tokens.accentFill : tokens.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    Icon(AppIcons.check,
                        size: AppSizes.icon16, color: tokens.accent),
                    const SizedBox(width: 6), // the design's own literal gap
                  ],
                  Flexible(
                    child: Text(
                      option.label,
                      style: AppText.ui.copyWith(
                        color: selected
                            ? tokens.textPrimary
                            : tokens.textSecondary,
                        fontWeight:
                            selected ? AppWeights.semi : AppWeights.medium,
                        fontFamily: AppFonts.sans,
                      ),
                    ),
                  ),
                ],
              ),
              if (option.hint != null) ...[
                const SizedBox(height: 3), // the design's own literal
                Text(
                  option.hint!,
                  style: AppText.micro.copyWith(
                    color: selected ? tokens.accent : tokens.textSecondary,
                    fontFamily: AppFonts.mono,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
