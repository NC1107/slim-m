// SPDX-License-Identifier: Apache-2.0
/// Fetches and caches one attachment's raw bytes.
///
/// In-memory only, per session: an attachment is content-addressed and
/// immutable once uploaded, so there is nothing to invalidate, but caching
/// it to disk on top of the server's own storage was not worth the extra
/// surface for what a self-hosted friend group's message history holds.
library;

import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart';

import 'cache_for.dart';
import 'providers.dart';

/// Deliberately small next to the avatar cache: these are whole images, and
/// the point is surviving a switch away and back rather than holding a
/// channel's history.
final _recent = KeepAliveCache(12);

final attachmentBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, attachmentId) async {
      // Far fewer than the avatars': an attachment can be megabytes.
      _recent.hold(ref, attachmentId);
      final fetched = await ref
          .watch(apiProvider)
          .fetchAttachment(attachmentId);
      return fetched.bytes;
    });
