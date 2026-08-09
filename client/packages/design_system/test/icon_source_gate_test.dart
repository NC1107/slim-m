// SPDX-License-Identifier: Apache-2.0
/// A raw `LucideIcons.` or Material `Icons.` reference outside [AppIcons] is
/// how the icon vocabulary stops being one vocabulary, one call site at a
/// time - the same drift [type_scale_literal_test] already gates on the type
/// scale.
///
/// `app/lib` cannot import `lucide_icons_flutter` at all (only
/// `design_system` depends on it, per each package's own `pubspec.yaml`), so
/// the Lucide half of this gate mostly guards against a future widget added
/// inside `design_system` itself reaching past [AppIcons]. The Material half
/// is the one with real reach: `Icons.*` ships bundled with
/// `package:flutter/material.dart`, already imported almost everywhere, so
/// nothing stops a raw `Icon(Icons.close)` from compiling today.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files allowed to reference an icon package directly, each with its own
/// one-line why. Empty on purpose: a widget that needs a glyph belongs in
/// [AppIcons], not at its own call site.
const _exceptions = <String>{};

final _lucideReference = RegExp(r'LucideIcons\.\w+');

/// `\b` before `Icons` is what keeps this from matching inside `AppIcons.` -
/// there is no word boundary between the `p` and the `I` of that identifier.
final _materialIconReference = RegExp(r'\bIcons\.\w+');

void main() {
  test('nothing outside AppIcons references an icon package directly', () {
    final designSystemLib = Directory('lib');
    expect(
      designSystemLib.existsSync(),
      isTrue,
      reason: 'run this from the design_system package root',
    );
    final appLib = Directory('../app/lib');
    expect(
      appLib.existsSync(),
      isTrue,
      reason: 'expected a sibling app package at ../app',
    );

    const appIconsFile = 'lib/src/app_icons.dart';
    final offenders = <String>[];
    for (final dir in [designSystemLib, appLib]) {
      for (final file in dir.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        if (file.path == appIconsFile) continue;
        if (_exceptions.contains(file.path)) continue;
        final content = file.readAsStringSync();
        for (final match in _lucideReference.allMatches(content)) {
          offenders.add('${file.path}: ${match.group(0)}');
        }
        for (final match in _materialIconReference.allMatches(content)) {
          offenders.add('${file.path}: ${match.group(0)}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'a raw icon-package reference was found outside AppIcons; add a '
          'named entry to AppIcons and reference that instead:\n'
          '${offenders.join('\n')}',
    );
  });
}
