// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/app_launch.dart';

const _apps = [
  api.App(
    moduleId: 'game-of-life',
    command: 'life',
    name: 'Game of Life',
    description: null,
  ),
];

void main() {
  test('matches an app by its module id', () {
    expect(matchApp(_apps, '/game-of-life')?.moduleId, 'game-of-life');
  });

  test('matches an app by its display name slugified, case-insensitively', () {
    expect(matchApp(_apps, '/Game-Of-Life')?.moduleId, 'game-of-life');
  });

  test('ignores any argument after the keyword: an app takes none', () {
    expect(matchApp(_apps, '/game-of-life whatever')?.moduleId, 'game-of-life');
  });

  test('no match for a non-slash message or an unknown keyword', () {
    expect(matchApp(_apps, 'game-of-life'), isNull);
    expect(matchApp(_apps, '/nope'), isNull);
    expect(matchApp(_apps, '/'), isNull);
    expect(matchApp(const [], '/game-of-life'), isNull);
  });
}
