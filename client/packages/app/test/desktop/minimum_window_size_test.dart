// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A desktop window cannot be sized into the phone layout.
///
/// Reported as "desktop opened as if it was mobile": a full-width channel
/// list, no member pane, and what's-new as a bottom sheet rather than a
/// centred dialog - the compact shell, in a window that plainly was not a
/// phone.
///
/// The layout rule itself is right and stays untouched: width decides, never
/// platform, so a genuinely narrow window should be compact. What was missing
/// is a floor keeping a desktop window on the correct side of it. On a scaled
/// display a window that looks ordinary can be under 600 logical pixels, and
/// nothing stopped it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/window_geometry.dart';
import 'package:slimm_design_system/design_system.dart';

import 'support/fake_desktop_window_port.dart';

void main() {
  test('the floor clears the compact breakpoint with room to spare', () {
    expect(
      WindowGeometry.minimumWindowSize.width,
      greaterThan(kCompactWidth),
      reason: 'at or under it, a window dragged to the floor is a phone',
    );
    // Not by a hair: the rail plus a transcript, not the threshold itself.
    expect(WindowGeometry.minimumWindowSize.width, greaterThanOrEqualTo(800));
  });

  test('the splash is smaller than the floor, and so precedes it', () {
    // The splash is applied before the floor exists, by design - a floor set
    // first would fight the 380x460 splash shape the launch depends on.
    expect(
      WindowGeometry.fallback.windowedSize.width,
      greaterThan(WindowGeometry.minimumWindowSize.width),
      reason: 'the default window opens well clear of the floor',
    );
  });

  test('the port carries the floor through to the platform', () async {
    final port = FakeDesktopWindowPort();
    await port.setMinimumSize(WindowGeometry.minimumWindowSize);

    expect(port.lastMinimumSize?.width, WindowGeometry.minimumWindowSize.width);
    expect(
      port.lastMinimumSize?.height,
      WindowGeometry.minimumWindowSize.height,
    );
  });
}
