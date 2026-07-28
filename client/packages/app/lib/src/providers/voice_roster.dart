// SPDX-License-Identifier: Apache-2.0
/// Who is in a voice channel the caller has not joined, kept current by
/// polling rather than any live event: the server has no push for this.
///
/// `autoDispose` and keyed per channel, so this only ever polls a channel a
/// rail row is actually rendering right now; scrolling one away or switching
/// servers cancels its timer with it. Ordinary rebuilds of that row do not
/// restart the poll: Riverpod caches the stream by channel id, so only the
/// interval below governs how often the network is actually touched.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'providers.dart';

/// How often an unjoined voice channel's roster is re-fetched. A real round
/// trip to the server's SFU, not a cheap read, so this stays well clear of a
/// per-frame or per-rebuild cost.
const voiceRosterPollInterval = Duration(seconds: 15);

/// Who the server reports as connected to [channelId]'s voice room.
///
/// A hidden participant is never in this list for any viewer but themselves;
/// the server enforces that, not this provider. An empty, present list means
/// a checked, genuinely empty room; [AsyncLoading] means not known yet, and
/// those two must not be rendered the same way.
///
/// A channel with no voice configured closes the stream on its first answer
/// rather than polling a server that will only ever say the same thing
/// again, which is why [AsyncLoading] is also what a text-only deployment
/// settles on forever. A transient failure - unreachable SFU, a blip in
/// authentication - adds nothing this tick and simply waits for the next
/// one, so the last roster this client actually saw stays on screen instead
/// of being cleared to looking empty.
final voiceRosterProvider = StreamProvider.autoDispose
    .family<List<api.VoiceRosterParticipant>, String>((ref, channelId) {
      final client = ref.watch(apiProvider);
      final controller = StreamController<List<api.VoiceRosterParticipant>>();

      Future<void> tick(Timer? self) async {
        try {
          final roster = await client.voiceRoster(channelId);
          if (!controller.isClosed) controller.add(roster);
        } on api.NotConfiguredException {
          self?.cancel();
          unawaited(controller.close());
        } on api.ApiException {
          // Unavailable, forbidden, rate-limited: try again on the next tick.
        }
      }

      late final Timer timer;
      timer = Timer.periodic(voiceRosterPollInterval, (_) => tick(timer));
      unawaited(tick(timer));

      ref.onDispose(() {
        timer.cancel();
        unawaited(controller.close());
      });

      return controller.stream;
    });
