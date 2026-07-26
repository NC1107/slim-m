// SPDX-License-Identifier: Apache-2.0
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_design_system/design_system.dart';

// WCAG 2.1 relative-luminance contrast, computed from the real design tokens so
// this file is the token contrast gate rather than a description of one.
//
// Two things the 2026-07-26 identity review changed here:
//
// - True black was never tested. The theme map held light and dark only, so the
//   one theme whose contrast is hardest, everything collapsing toward #000000,
//   was the one nothing checked.
// - Code block colours are gated now. Five roles across three themes is fifteen
//   values, and a fenced block is exactly the surface that quietly ends up the
//   single inaccessible thing in an otherwise AA product.
//
// Borders stay reported rather than asserted, which is a deliberate open
// question rather than an oversight; the reason is written above that test.

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

void _expectAA(Color fg, Color bg, String what) {
  expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: what);
}

void main() {
  final themes = {
    'light': AppTokens.light,
    'dark': AppTokens.dark,
    'trueBlack': AppTokens.trueBlack,
  };

  themes.forEach((name, t) {
    test('$name body text and accent meet WCAG AA', () {
      for (final surface in [t.surfaceSunken, t.surfaceBase, t.surfaceRaised]) {
        _expectAA(t.textPrimary, surface, '$name primary text');
        _expectAA(t.textSecondary, surface, '$name secondary text');
        _expectAA(t.accent, surface, '$name accent as text');
      }
    });

    test('$name accent fill is legible with what sits on it', () {
      // The pair a split accent exists to make checkable: the fill is
      // brand-true rather than contrast-bound, so what matters is the text on
      // top of it, not the fill against the page behind it.
      _expectAA(t.accentOn, t.accentFill, '$name accentOn over accentFill');
    });

    test('$name code block colours meet WCAG AA', () {
      for (final role in t.code.all) {
        _expectAA(role, t.surfaceRaised, '$name code role on raised surface');
      }
    });

    // Not asserted, on purpose, and the reason is worth writing down rather
    // than leaving as a silent omission.
    //
    // WCAG 1.4.11 asks 3:1 of a UI component boundary. Reaching that on
    // #000000 needs roughly #5A5A5A, which is not a hairline any more, it is a
    // visible grey rule, and it would undo the border-first look the token
    // exists to serve. The identity review raised true black from #23282D to
    // #2C3238, a real improvement (1.41:1 to 1.62:1) and still nowhere near
    // 3:1.
    //
    // So the open question is not the value, it is whether a separator hairline
    // counts as a UI component under 1.4.11 or as an incidental boundary that
    // is exempt. Until that is settled these print, so a regression shows up in
    // CI output and the numbers cannot silently drift.
    test('$name border contrast is reported, not gated', () {
      for (final entry in {
        'sunken': t.surfaceSunken,
        'base': t.surfaceBase,
        'raised': t.surfaceRaised,
      }.entries) {
        final value = _contrast(t.borderSubtle, entry.value).toStringAsFixed(2);
        // ignore: avoid_print
        print('$name border on ${entry.key}: $value:1 (target 3.0, unsettled)');
      }
    });
  });

  test('canvas cursor hues are a closed set of six distinct values', () {
    // Categorical identity for remote participants. They only work as identity
    // if no two read as the same colour, which is the property worth pinning
    // rather than any particular hex.
    final cursors = AppCanvasColors.cursors;
    expect(cursors, hasLength(6));
    expect(cursors.toSet(), hasLength(6), reason: 'no duplicate cursor hues');
  });
}
