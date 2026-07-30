// SPDX-License-Identifier: Apache-2.0
/// Reading a server's advertised capabilities off `/version`.
///
/// The distinction these tests exist for is unknown versus missing. Both are
/// "not present", and treating them the same would have the client tell
/// someone an older server has no safety tools when it has simply never been
/// asked.
library;

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

Version _version(Map<String, Object?> extra) => Version.fromJson({
      'name': 'slim-m',
      'version': '0.17.0',
      'protocol': 1,
      ...extra,
    });

void main() {
  group('advertised capabilities', () {
    test('a server naming both report and block has its safety tools', () {
      final version = _version({
        'capabilities': ['block', 'report'],
      });
      expect(version.safetyTools, SafetyTools.present);
      expect(version.missingSafetyTools, isEmpty);
    });

    test('a server naming neither is missing both, in a stated order', () {
      final version = _version({'capabilities': <String>[]});
      expect(version.safetyTools, SafetyTools.missing);
      expect(version.missingSafetyTools, ['report', 'block']);
    });

    test('a server naming one is missing only the other', () {
      final version = _version({
        'capabilities': ['block'],
      });
      expect(version.safetyTools, SafetyTools.missing);
      expect(version.missingSafetyTools, ['report']);
    });

    test('a server too old to answer is unknown, never missing', () {
      final version = _version({});
      expect(version.capabilities, isNull);
      expect(version.safetyTools, SafetyTools.unknown);
    });

    test('a capability list that is not a list is unknown too', () {
      expect(
        _version({'capabilities': 'report,block'}).safetyTools,
        SafetyTools.unknown,
      );
    });

    test(
        'a capability the client does not know about is carried, not '
        'dropped, and does not count as a safety tool', () {
      final version = _version({
        'capabilities': ['block', 'report', 'something-new'],
      });
      expect(version.capabilities, contains('something-new'));
      expect(version.safetyTools, SafetyTools.present);
    });
  });
}
