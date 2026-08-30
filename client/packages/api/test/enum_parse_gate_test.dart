// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Forbids `values.byName` anywhere under `packages/api/lib`.
///
/// `byName` throws a bare `ArgumentError` on a value it does not recognise,
/// and that is not an `ApiException`, so it escapes every `on ApiException`
/// handler in the app and surfaces as an unhandled error. That breaks this
/// repo's additive-only wire contract, which promises a client keeps working
/// against a server that has grown a value it has never heard of. Every wire
/// enum needs its own tolerant `parse` instead, in the shape of
/// `JoinPolicy.parse`: a plain function that maps an unrecognised value to a
/// deliberately chosen, documented fallback rather than throwing.
///
/// A Dart test here, rather than a shell grep in `hygiene.yml`, because the
/// concern is scoped to this one package's source, the same way
/// `schema_coverage_test.dart` already reads this package's own files rather
/// than reaching for a repo-wide gate; it also runs on every local `flutter
/// test` in this package, not only in CI.
library;

import 'dart:io';

import 'package:test/test.dart';

/// Matches `Foo.values.byName(...)`, not the unrelated `byName` identifier
/// `packages/app` uses as a `Comparator` name (no `.values.` before it).
final RegExp _byNameCall = RegExp(r'\.values\.byName\(');

void main() {
  final repoRoot = _findRepoRoot(Directory.current);
  final libDir = Directory('${repoRoot.path}/client/packages/api/lib');

  test('no source under packages/api/lib parses an enum with values.byName',
      () {
    final hits = _scan(libDir);
    expect(
      hits,
      isEmpty,
      reason: '\nvalues.byName throws ArgumentError on an unrecognised wire '
          'value, which escapes every `on ApiException` handler in the app. '
          'Give the enum a tolerant `parse` instead (see JoinPolicy.parse):'
          '\n\n${hits.join('\n')}\n',
    );
  });

  // Proves the gate above can actually say no, not pass vacuously.
  test('the scanner catches values.byName when it is actually present', () {
    final tmp = Directory.systemTemp.createTempSync('byname_gate_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/offender.dart').writeAsStringSync(
      "final x = SomeEnum.values.byName(json['field'] as String);\n",
    );

    expect(_scan(tmp), isNotEmpty);
  });

  test('the scanner does not flag the unrelated byName identifier', () {
    final tmp = Directory.systemTemp.createTempSync('byname_gate_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    File('${tmp.path}/comparator.dart').writeAsStringSync(
      'int byName(Profile a, Profile b) => a.name.compareTo(b.name);\n',
    );

    expect(_scan(tmp), isEmpty);
  });
}

/// Walks upward from [start] looking for schema/openapi.yaml, the same
/// repo-root anchor `schema_coverage_test.dart` uses, so this test does not
/// depend on which directory `dart test` or `flutter test` was invoked from.
Directory _findRepoRoot(Directory start) {
  var dir = start.absolute;
  for (var i = 0; i < 10; i++) {
    if (File('${dir.path}/schema/openapi.yaml').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail(
    'could not find schema/openapi.yaml walking up from ${start.path}; is '
    'this test running from somewhere inside the slim-m repo?',
  );
}

/// Returns one `path:line: content` string per `values.byName` call found
/// under [dir], recursively, in any `.dart` file.
List<String> _scan(Directory dir) {
  final hits = <String>[];
  final files = dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (_byNameCall.hasMatch(lines[i])) {
        hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
      }
    }
  }
  return hits;
}
