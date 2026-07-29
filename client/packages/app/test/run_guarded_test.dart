// SPDX-License-Identifier: Apache-2.0
/// What a guarded action tells the user when it fails.
///
/// The rule this pins is the one the twenty-six hand-written copies broke:
/// a server's own explanation of a bad request is worth reading, and a
/// transport exception's Dart string is not. Nothing here may put an
/// exception's `toString` in front of a person.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/widgets/run_guarded.dart';

void main() {
  test('success returns no failure at all', () async {
    final failure = await runGuarded(
      whatFailed: 'revoke the invite',
      action: () async {},
    );
    expect(failure, isNull);
  });

  test('a bad request carries the server\'s own explanation', () async {
    final failure = await runGuarded(
      whatFailed: 'create the role',
      action: () async => throw const api.BadRequestException(
        'name must be 1 to 32 characters',
      ),
    );
    expect(
      failure,
      'Could not create the role. name must be 1 to 32 characters',
    );
  });

  test('a transport failure never leaks the exception string', () async {
    final failure = await runGuarded(
      whatFailed: 'revoke the invite',
      action: () async => throw const api.TransportException(
        'POST /invites/x/revoke failed: SocketException: refused',
      ),
    );
    expect(failure, isNotNull);
    expect(failure, contains('could not be reached'));
    expect(
      failure,
      isNot(contains('SocketException')),
      reason: 'a Dart exception string helps nobody and reads as a crash',
    );
    expect(
      failure,
      contains('Nothing was changed'),
      reason: 'the error grammar says so wherever trust is at stake',
    );
  });

  test('a refusal says it was a refusal, not a mystery', () async {
    final failure = await runGuarded(
      whatFailed: 'delete the role',
      action: () async => throw const api.UnauthorizedException('nope'),
    );
    expect(failure, contains('not allowed'));
  });

  test('every failure names the action it was', () async {
    for (final thrown in <api.ApiException>[
      const api.TransportException('x'),
      const api.UnauthorizedException('nope'),
      const api.RateLimitedException('slow down'),
      const api.ConflictException('taken'),
    ]) {
      final failure = await runGuarded(
        whatFailed: 'save the change',
        action: () async => throw thrown,
      );
      expect(failure, contains('save the change'), reason: '$thrown');
    }
  });
}
