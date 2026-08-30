// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The one WCAG contrast computation this package needs: which of black or
/// white a cursor's own name-chip label should use.
///
/// Split out of `canvas_live_painters.dart` to keep that file inside the
/// review budget; [cursorLabelColorFor] is the only thing it exports.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// The label colour a cursor's own name chip should use: whichever of pure
/// black or pure white reaches the higher WCAG contrast against [swatch].
///
/// The six cursor hues are a closed, deliberately warmer-than-chrome palette
/// (see `AppCanvasColors.cursors`' own doc, in the app layer this package
/// cannot depend on) and none of them were chosen with a fixed white label on
/// top in mind - measured, three of the six read under the WCAG 1.4.3 large
/// text floor of 3:1 against white, and none clear the 4.5:1 body-text floor
/// this design system holds every other colour pair to. Retuning the palette
/// itself to fix a text-colour problem would risk the one thing about it that
/// already works: the six hues read as one coherent, considered set. Deriving
/// the label from each swatch's own luminance instead leaves the palette
/// alone and clears the floor for every one of them, checked in
/// `cursor_label_contrast_test.dart`.
Color cursorLabelColorFor(Color swatch) {
  const black = Color(0xFF000000);
  const white = Color(0xFFFFFFFF);
  return _contrastRatio(swatch, black) >= _contrastRatio(swatch, white)
      ? black
      : white;
}

double _channel(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _relativeLuminance(Color color) =>
    0.2126 * _channel(color.r) +
    0.7152 * _channel(color.g) +
    0.0722 * _channel(color.b);

double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
