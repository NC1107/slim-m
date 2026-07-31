// SPDX-License-Identifier: Apache-2.0
/// Which user a DM channel is with.
///
/// A DM's local [Channel] row carries the other participant's display name
/// (see `dms.dart`), never their id, so a caller that needs the id - telling
/// whether the person on the other end of this DM is blocked - has to ask
/// the server directly. There is no per-channel lookup for it, only the full
/// listing `GET /dms` already answers.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart';

import 'providers.dart';

/// The other participant's id for the DM at [channelId], or null once
/// resolved against a listing that does not carry it: [channelId] is not a
/// DM at all, or is one this account can no longer see.
final dmParticipantProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, channelId) async {
      final client = ref.watch(apiProvider);
      final dms = await client.listDirectMessages();
      for (final dm in dms) {
        if (dm.channelId == channelId) return dm.user.id;
      }
      return null;
    });
