// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Parsing a forwarded message off the wire.
///
/// `forwarded` is always present as a key and null on a message that
/// forwards nothing - the same "null means genuinely none" convention `poll`
/// follows - so an absent key and a null one must parse identically, and an
/// older server that never heard of forwards must parse like one that simply
/// has none.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:slimm_api/api.dart';

Map<String, dynamic> _message(String extra) =>
    jsonDecode('{"id":"m1","channel_id":"c1","author_id":"u1",'
        '"author_display_name":"Bob","seq":4,"content":"look at this",'
        '"created_at":1000,"edited_at":null$extra}') as Map<String, dynamic>;

void main() {
  test('a forward carries the original, not the forwarder', () {
    final message = Message.fromJson(
      _message(',"forwarded":{"message_id":"m0","channel_id":"c0",'
          '"author_id":"u0","author_display_name":"Alice",'
          '"author_avatar_updated_at":77,"created_at":10,'
          '"content":"the original text"}'),
    );

    expect(message.authorDisplayName, 'Bob', reason: 'who forwarded it');
    expect(message.content, 'look at this', reason: "the forwarder's own note");

    final forwarded = message.forwarded!;
    expect(forwarded.messageId, 'm0');
    expect(forwarded.channelId, 'c0');
    expect(forwarded.authorDisplayName, 'Alice');
    expect(forwarded.authorAvatarUpdatedAt, 77);
    expect(forwarded.content, 'the original text');
    expect(
      forwarded.createdAt,
      10,
      reason: "the original's own timestamp, not the forward's 1000",
    );
  });

  test('an explicit null and an absent key both mean forwarding nothing', () {
    expect(Message.fromJson(_message(',"forwarded":null')).forwarded, null);
    expect(Message.fromJson(_message('')).forwarded, null);
  });

  test('an anonymized original author leaves the snapshot readable', () {
    final message = Message.fromJson(
      _message(',"forwarded":{"message_id":"m0","channel_id":"c0",'
          '"author_id":null,"author_display_name":null,'
          '"author_avatar_updated_at":null,"created_at":10,'
          '"content":"still here"}'),
    );

    final forwarded = message.forwarded!;
    expect(forwarded.authorId, null);
    expect(forwarded.authorDisplayName, null);
    expect(
      forwarded.content,
      'still here',
      reason: 'the snapshot outlives its author, exactly as it outlives its '
          'original',
    );
  });
}
