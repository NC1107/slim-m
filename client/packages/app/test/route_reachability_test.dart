// SPDX-License-Identifier: Apache-2.0
/// Every route the app can show must be somewhere the user can get to.
///
/// This exists because `Routes.settings` was registered, built, and tested,
/// and nothing in the running app ever navigated to it. Sign-out, the device
/// list and account deletion all live behind it, so the whole screen was dead
/// weight and the app had no way to sign out at all. Nothing caught it: the
/// route resolved, the screen rendered under test, and every widget test that
/// touched settings pushed it directly.
///
/// So this checks the one thing those could not - that something other than
/// the route's own registration mentions it - by reading the source, the same
/// way the server's OpenAPI contract test reads the router. A route is not a
/// feature until something links to it.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Registering a route says a path exists; it says nothing about a user ever
/// arriving there. `path: Routes.x` is exactly the evidence this test must not
/// accept, since that line was present for settings the whole time.
final _registration = RegExp(r'path:\s*Routes\.\w+');

/// Likewise a redirect guard asking "are we already here" - true of a route
/// nobody can reach.
final _locationCheck = RegExp(r'location\s*==\s*Routes\.\w+');

/// A whole-line comment. Prose naming a route is not a link to it, and this
/// test caught itself passing on the comment above the very button it was
/// written to protect. Only whole-line comments are stripped, so a `//` inside
/// a url literal is left alone.
final _comment = RegExp(r'^\s*//.*$', multiLine: true);

void main() {
  test('every route is reachable from somewhere in the app', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue,
        reason: 'run this from the app package root');

    final routesFile = File('lib/src/routing/routes.dart');
    final names = RegExp(r'static const (\w+) =')
        .allMatches(routesFile.readAsStringSync())
        .map((m) => m.group(1)!)
        // A go_router pattern is matched against, never navigated to.
        .where((name) => !name.endsWith('Pattern'))
        .toSet();
    expect(names, isNotEmpty, reason: 'no routes found to check');

    final uses = lib
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.absolute.path != routesFile.absolute.path)
        .map((f) => f.readAsStringSync())
        .join('\n')
        .replaceAll(_comment, '')
        .replaceAll(_registration, '')
        .replaceAll(_locationCheck, '');

    final unreachable = names
        .where((name) => !RegExp('Routes\\.$name\\b').hasMatch(uses))
        .toList()
      ..sort();

    expect(
      unreachable,
      isEmpty,
      reason: 'these routes are registered but nothing sends a user to them, '
          'so the screens behind them cannot be opened: '
          '${unreachable.join(', ')}',
    );
  });
}
