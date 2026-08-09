// SPDX-License-Identifier: Apache-2.0
/// Four Flutter-owned widgets each drive their own entrance or expansion
/// with a plain `AnimationController` the framework creates internally, keyed
/// to the platform's own reduce-motion accessibility feature - never to this
/// app's [MotionOverride], which only ever reaches `MediaQuery` and cannot
/// touch a controller Flutter owns.
///
/// Found by hand, once each, in `showAppSheet` (`sheet.dart`), the compact
/// branch of `showMemberProfile` (`member_profile.dart`), and the debug
/// log's `ExpansionTile` (`debug_log_screen.dart`); the desktop popover a few
/// lines below the second of those already routed `transitionDuration`
/// straight through `AppMotion.reduced`, which is what `showGeneralDialog`'s
/// own inclusion below is modelled on. This is the sweep those three fixes
/// did not leave behind anywhere else, the same shape
/// `type_scale_literal_test.dart` already keeps for an off-scale font size.
///
/// A per-file occurrence count, not a per-call parse: cheap, and every rule
/// here already holds file-wide today, so a call that carries the override
/// and a sibling call in the same file that does not would pass this gate
/// undetected. That trade is the one `type_scale_literal_test.dart` already
/// made for the same reason - a real parser is a second thing to maintain
/// and drift from the grammar it parses.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class _Rule {
  const _Rule(this.name, this.call, this.override);

  /// What a failure names this widget as.
  final String name;

  /// The widget's own call or constructor, generics included.
  final RegExp call;

  /// The keyword argument that carries `AppMotion` through to it.
  final String override;
}

final _rules = [
  _Rule('showDialog', RegExp(r'\bshowDialog(<[^>]*>)?\('), 'animationStyle:'),
  _Rule(
    'showModalBottomSheet',
    RegExp(r'\bshowModalBottomSheet(<[^>]*>)?\('),
    'sheetAnimationStyle:',
  ),
  _Rule(
    'showGeneralDialog',
    RegExp(r'\bshowGeneralDialog(<[^>]*>)?\('),
    'transitionDuration:',
  ),
  _Rule('ExpansionTile', RegExp(r'\bExpansionTile\('),
      'expansionAnimationStyle:'),
];

/// A short, named allowlist rather than a growing one: each entry would
/// carry its own one-line "why" in the source, the same discipline
/// `type_scale_literal_test.dart` already holds everyone else to.
const _exceptions = <String>{};

void main() {
  test(
    'every Flutter-owned dialog, sheet or expansion carries this app\'s own '
    'reduce-motion override',
    () {
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

      final offenders = <String>[];
      for (final dir in [designSystemLib, appLib]) {
        for (final file in dir.listSync(recursive: true).whereType<File>()) {
          if (!file.path.endsWith('.dart')) continue;
          if (_exceptions.contains(file.path)) continue;
          final source = file.readAsStringSync();
          for (final rule in _rules) {
            final calls = rule.call.allMatches(source).length;
            if (calls == 0) continue;
            final overrides = rule.override.allMatches(source).length;
            if (calls > overrides) {
              offenders.add(
                '${file.path}: ${rule.name} appears $calls time(s) but '
                '${rule.override} only $overrides time(s)',
              );
            }
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason: 'a Flutter-owned dialog/sheet/expansion with no in-app '
            'reduce-motion override - route its duration through '
            'AppMotion.reduced or AnimationStyle.noAnimation, or add a '
            'one-line "why" comment and list the file in _exceptions:\n'
            '${offenders.join('\n')}',
      );
    },
  );
}
