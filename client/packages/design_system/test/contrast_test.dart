// SPDX-License-Identifier: Apache-2.0
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

// WCAG 2.1 relative-luminance contrast, computed from the real design tokens so
// this test is the token contrast gate. Body text and accent must reach 4.5:1.
// The border values are known-provisional (tracked in the design track), so
// they are reported rather than asserted until a designer review locks them.

double _channel(int v) {
  final c = v / 255.0;
  if (c <= 0.03928) return c / 12.92;
  return math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _luminance(Color color) {
  final argb = color.toARGB32();
  final r = _channel((argb >> 16) & 0xFF);
  final g = _channel((argb >> 8) & 0xFF);
  final b = _channel(argb & 0xFF);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void _expectAA(Color fg, Color bg) {
  expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5));
}

void main() {
  final themes = {'light': AppTokens.light, 'dark': AppTokens.dark};

  themes.forEach((name, t) {
    test('$name body text and accent meet WCAG AA', () {
      _expectAA(t.textPrimary, t.surfaceBase);
      _expectAA(t.textPrimary, t.surfaceRaised);
      _expectAA(t.textSecondary, t.surfaceBase);
      _expectAA(t.textSecondary, t.surfaceRaised);
      _expectAA(t.accent, t.surfaceBase);
      _expectAA(t.accent, t.surfaceRaised);
    });

    test('$name border contrast is reported, not gated', () {
      final onBase = _contrast(t.borderSubtle, t.surfaceBase);
      final onRaised = _contrast(t.borderSubtle, t.surfaceRaised);
      final b = onBase.toStringAsFixed(2);
      final r = onRaised.toStringAsFixed(2);
      // ignore: avoid_print
      print('$name border: base $b:1, raised $r:1 (target 3.0, provisional)');
    });
  });
}
