// SPDX-License-Identifier: Apache-2.0
/// A raw `LucideIcons.`, Material `Icons.` or `CupertinoIcons.` reference
/// outside [AppIcons] is how the icon vocabulary stops being one vocabulary,
/// one call site at a time - the same drift [type_scale_literal_test]
/// already gates on the type scale.
///
/// `app/lib` cannot import `lucide_icons_flutter` at all (only
/// `design_system` depends on it, per each package's own `pubspec.yaml`), so
/// the Lucide half of this gate mostly guards against a future widget added
/// inside `design_system` itself reaching past [AppIcons]. The other two have
/// real reach today: `Icons.*` ships bundled with `package:flutter/material.dart`,
/// already imported almost everywhere, and `CupertinoIcons.*` needs no pubspec
/// dependency at all - it is defined in the Flutter SDK's own
/// `package:flutter/cupertino.dart`, one import away from any file. Nothing
/// stops a raw `Icon(Icons.close)` or `Icon(CupertinoIcons.heart)` from
/// compiling today.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files allowed to reference an icon package directly, each with its own
/// one-line why. Empty on purpose: a widget that needs a glyph belongs in
/// [AppIcons], not at its own call site.
const _exceptions = <String>{};

final _lucideReference = RegExp(r'LucideIcons\.\w+');

/// A named provider matched in full, never by a bare `\bIcons\.` boundary
/// check alone: that shape missed `CupertinoIcons.heart` outright, since
/// there is no word boundary between the `o` and the `I` of that identifier
/// either - the same non-boundary `AppIcons.` already relies on to stay
/// unmatched. Reproduced directly: a `CupertinoIcons.heart` reference
/// planted in `design_system/lib` passed this gate silently before this list
/// grew a third entry.
final _iconProviderReferences = [
  RegExp(r'\bIcons\.\w+'),
  RegExp(r'CupertinoIcons\.\w+'),
];

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
        for (final pattern in _iconProviderReferences) {
          for (final match in pattern.allMatches(content)) {
            offenders.add('${file.path}: ${match.group(0)}');
          }
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

  /// The regex-level regression for the `CupertinoIcons` gap: reverting the
  /// second pattern in [_iconProviderReferences] fails exactly this test,
  /// since the file-scan test above only fails when the real tree carries an
  /// offender, and this tree carries none right now.
  test(
      'the material pattern list reaches Icons and CupertinoIcons alike, '
      'and never AppIcons', () {
    bool matchesAny(String source) =>
        _iconProviderReferences.any((p) => p.hasMatch(source));

    expect(matchesAny('Icon(Icons.close)'), isTrue);
    expect(matchesAny('Icon(CupertinoIcons.heart)'), isTrue);
    expect(
      matchesAny('AppIcons.close'),
      isFalse,
      reason: 'must never fire on the vocabulary it exists to allow',
    );
  });
}
