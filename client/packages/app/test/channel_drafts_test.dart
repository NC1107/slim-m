// SPDX-License-Identifier: Apache-2.0
/// `ChannelDraftsController` in isolation: the plain get/save/clear
/// contract, and the sign-out and account-switch wipes that close the same
/// leak `BlocksController` already closed (a draft is the same shape as a
/// blocked-user list - session state a device must not hand to whoever
/// signs in next).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/channel_drafts.dart';
import 'package:slimm_app/src/providers/providers.dart';

const _alice = api.TokenPair(
  userId: 'alice',
  accessToken: 'a-access',
  refreshToken: 'a-refresh',
  accessExpiresAt: 0,
);

const _bob = api.TokenPair(
  userId: 'bob',
  accessToken: 'b-access',
  refreshToken: 'b-refresh',
  accessExpiresAt: 0,
);

void main() {
  late api.SessionStore session;
  late ProviderContainer container;

  setUp(() {
    session = api.SessionStore(tokens: _alice);
    container = ProviderContainer(
      overrides: [sessionProvider.overrideWithValue(session)],
    );
    addTearDown(container.dispose);
  });

  test('a channel with nothing saved has an empty draft', () {
    final drafts = container.read(channelDraftsProvider);
    expect(drafts.draftFor('c1'), isEmpty);
  });

  test('saving and reading back a draft round-trips per channel', () {
    final drafts = container.read(channelDraftsProvider);
    drafts.save('c1', 'hello there');
    drafts.save('c2', 'a different message');

    expect(drafts.draftFor('c1'), 'hello there');
    expect(drafts.draftFor('c2'), 'a different message');
  });

  test('saving an empty string forgets the draft rather than keeping one', () {
    final drafts = container.read(channelDraftsProvider);
    drafts.save('c1', 'hello there');
    drafts.save('c1', '');

    expect(
      drafts.draftFor('c1'),
      isEmpty,
      reason:
          'an empty draft and no draft must read the same way, or a '
          'channel visited and left empty grows the map forever',
    );
  });

  test('clear forgets a channel outright, called once its text is sent', () {
    final drafts = container.read(channelDraftsProvider);
    drafts.save('c1', 'hello there');
    drafts.clear('c1');

    expect(drafts.draftFor('c1'), isEmpty);
  });

  test('signing out empties every draft', () async {
    final drafts = container.read(channelDraftsProvider);
    drafts.save('c1', 'hello there');

    session.set(null);
    // The session's changes are a broadcast stream, delivered on a microtask.
    await Future<void>.value();

    expect(
      drafts.draftFor('c1'),
      isEmpty,
      reason:
          'the local database is one file for the whole app; a draft '
          'outliving sign-out would hand it to whoever signs in next',
    );
  });

  test(
    'a different account signing in on this process empties every draft',
    () async {
      final drafts = container.read(channelDraftsProvider);
      drafts.save('c1', 'hello there');

      session.set(_bob);
      await Future<void>.value();

      expect(drafts.draftFor('c1'), isEmpty);
    },
  );

  test('a token rotation for the same account keeps its drafts', () async {
    final drafts = container.read(channelDraftsProvider);
    drafts.save('c1', 'hello there');

    session.set(
      const api.TokenPair(
        userId: 'alice',
        accessToken: 'rotated-access',
        refreshToken: 'rotated-refresh',
        accessExpiresAt: 1000,
      ),
    );
    await Future<void>.value();

    expect(
      drafts.draftFor('c1'),
      'hello there',
      reason:
          'the session stream also fires on routine access-token rotation, '
          'not just a real account change',
    );
  });
}
