// SPDX-License-Identifier: Apache-2.0
/// [describeApiFailure] is the one place any caller, guarded by `runGuarded`
/// or not, turns an [ApiException] into a sentence. This pins the mapping
/// directly, beneath `run_guarded_test.dart`'s behavioural tests.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/api_failure.dart';

void main() {
  test('a transport failure never leaks the exception string', () {
    final message = describeApiFailure(
      'join the call',
      const api.TransportException(
        'POST /voice/token failed: SocketException: refused',
      ),
    );
    expect(message, isNot(contains('SocketException')));
    expect(message, isNot(contains('POST /voice/token')));
    expect(message, contains('the server could not be reached'));
    expect(message, contains('Nothing was changed'));
  });

  test('a bad request keeps the server\'s own reason', () {
    expect(
      describeApiFailure(
        'create the role',
        const api.BadRequestException('name must be 1 to 32 characters'),
      ),
      'Could not create the role. name must be 1 to 32 characters',
    );
  });

  test('a conflict keeps the server\'s own reason', () {
    expect(
      describeApiFailure(
        'set the overwrite',
        const api.ConflictException('already exists'),
      ),
      'Could not set the overwrite. already exists',
    );
  });

  test('a forbidden and an unauthorized read differently', () {
    final forbidden = describeApiFailure(
      'delete the role',
      const api.ForbiddenException('nope'),
    );
    final unauthorized = describeApiFailure(
      'delete the role',
      const api.UnauthorizedException('nope'),
    );
    expect(forbidden, contains('not allowed'));
    expect(unauthorized, contains('signed out'));
    expect(unauthorized, isNot(contains('not allowed')));
  });

  test('a rate limit and an unnamed server error each name the action', () {
    for (final thrown in <api.ApiException>[
      const api.RateLimitedException('slow down'),
      const api.ServerException('boom', 500),
      const api.UnavailableException('busy'),
      const api.NotConfiguredException('no sfu'),
      const api.NotFoundException('gone'),
    ]) {
      expect(
        describeApiFailure('save the change', thrown),
        contains('save the change'),
        reason: '$thrown',
      );
    }
  });
}
