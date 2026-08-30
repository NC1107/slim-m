// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Client-generated identifiers.
library;

import 'dart:math';

/// Generates the UUIDv7 that identifies a message and makes its send
/// idempotent. Time-ordered, which is what the server's storage assumes.
///
/// Shared by the ordinary send path and the poll composer, both of which
/// need a client-generated id before the server has ever seen the message.
String newMessageId() => _uuidV7();

/// The same generator for a canvas object, which is idempotent by id the same
/// way a message send is. Named separately so a call site says which stream it
/// belongs to.
String newCanvasObjectId() => _uuidV7();

/// The same generator for a canvas op (`remove`, `clear`, `restore`, `move`),
/// which is idempotent by id the same way a placement is.
String newCanvasOpId() => _uuidV7();

/// The same generator for an in-flight stroke preview session. Never a real
/// canvas object id: it only keys an ephemeral relay frame, and the object(s)
/// a finished stroke commits are minted separately by [newCanvasObjectId]
/// once the gesture ends.
String newCanvasDraftId() => _uuidV7();

String _uuidV7() {
  final now = DateTime.now().millisecondsSinceEpoch;
  final random = Random.secure();
  final bytes = <int>[
    (now >> 40) & 0xff,
    (now >> 32) & 0xff,
    (now >> 24) & 0xff,
    (now >> 16) & 0xff,
    (now >> 8) & 0xff,
    now & 0xff,
    ...List<int>.generate(10, (_) => random.nextInt(256)),
  ];
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}'
      '-${hex.substring(16, 20)}-${hex.substring(20)}';
}
