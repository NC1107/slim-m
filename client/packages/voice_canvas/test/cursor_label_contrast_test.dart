// SPDX-License-Identifier: Apache-2.0
/// Every cursor swatch's own derived label colour clears the WCAG 2.1 AA
/// body-text floor, and the WCAG formula itself, so a seventh hue can never
/// be added to the palette below that floor without this failing first.
///
/// The formula mirrors `design_system/test/contrast_test.dart`'s own, which
/// this package cannot import (it carries no dependency on the design
/// system at all - see `canvas_painters.dart`'s own library doc); the six
/// literal colours below are `AppCanvasColors.cursors`, copied verbatim for
/// the same reason `visual_tokens.dart` already copies the rest of it.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_voice_canvas/src/canvas_painters.dart';

const _cursorPalette = <Color>[
  Color(0xFFE0699A),
  Color(0xFF8C6FE0),
  Color(0xFF3FA9C9),
  Color(0xFFD98A3F),
  Color(0xFF6FBF73),
  Color(0xFFC96FB8),
];

double _channel(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color color) =>
    0.2126 * _channel(color.r) +
    0.7152 * _channel(color.g) +
    0.0722 * _channel(color.b);

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final swatch in _cursorPalette) {
    test(
        'cursor swatch $swatch clears AA body text against its own label '
        'colour', () {
      final label = cursorLabelColorFor(swatch);
      expect(
        _contrast(swatch, label),
        greaterThanOrEqualTo(4.5),
        reason: 'a fixed white label fails this for three of the six real '
            'swatches; the label must be derived from the swatch, not fixed',
      );
    });
  }

  test('cursorLabelColorFor always answers pure black or pure white', () {
    for (final swatch in _cursorPalette) {
      expect(
        cursorLabelColorFor(swatch),
        anyOf(const Color(0xFF000000), const Color(0xFFFFFFFF)),
      );
    }
  });
}
