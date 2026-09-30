// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The canvas pan glyph is the hand, not the four-way arrows.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:slimm_design_system/design_system.dart';

void main() {
  test('AppIcons.pan is the Lucide hand and not the move arrows', () {
    expect(AppIcons.pan, LucideIcons.hand300);
    expect(AppIcons.pan, isNot(LucideIcons.move300));
  });
}
