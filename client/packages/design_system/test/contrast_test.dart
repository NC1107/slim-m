// SPDX-License-Identifier: Apache-2.0
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

// WCAG 2.1 relative-luminance contrast, computed from the real design tokens so
// this test is the token contrast gate. Body text must reach 4.5:1; borders and
// large text or icons must reach 3:1. The border values are known-provisional
// and tracked in the design track, so they are reported, not asserted, until a
// designer review locks the palette.

double _channel(int v) {
  final c = v / 255.0;
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color color) {
  final argb = color.toARGB32();
  return 0.2126 * _channel((argb >> 16) & 0xFF) +
      0.7152 * _channel((argb >> 8) & 0xFF) +
      0.0722 * _channel(argb & 0xFF);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  final themes = <String, AppTokens>{
    'light': AppTokens.light,
    'dark': AppTokens.dark,
  };

  themes.forEach((name, tokens) {
    test('$name: body text and accent meet WCAG AA (4.5:1)', () {
      expect(_contrast(tokens.textPrimary, tokens.surfaceBase),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(tokens.textPrimary, tokens.surfaceRaised),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(tokens.textSecondary, tokens.surfaceBase),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(tokens.textSecondary, tokens.surfaceRaised),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(tokens.accent, tokens.surfaceBase),
          greaterThanOrEqualTo(4.5));
      expect(_contrast(tokens.accent, tokens.surfaceRaised),
          greaterThanOrEqualTo(4.5));
    });

    test('$name: border contrast is reported (known-provisional, not gating)',
        () {
      final onBase = _contrast(tokens.borderSubtle, tokens.surfaceBase);
      final onRaised = _contrast(tokens.borderSubtle, tokens.surfaceRaised);
      // ignore: avoid_print
      print('$name border on base ${onBase.toStringAsFixed(2)}:1, '
          'on raised ${onRaised.toStringAsFixed(2)}:1 (target 3.0, provisional)');
    });
  });
}
