// SPDX-License-Identifier: Apache-2.0
/// Who is in a voice channel the caller has not joined, kept current by
/// polling, now nudged promptly by a live event rather than waiting out the
/// interval.
///
/// `autoDispose` and keyed per channel, so this only ever polls a channel a
/// rail row is actually rendering right now; scrolling one away or switching
/// servers cancels its timer with it. Ordinary rebuilds of that row do not
/// restart the poll: Riverpod caches the stream by channel id, so only the
/// interval below governs the network's steady-state cost.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'live_events.dart';
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
/// This client's own identity is dropped from every answer, always. Whether
/// this client is in the call is `voiceControllerProvider`'s job, driven by
/// the live session, never this roster's: the SFU only reaps a dead
/// connection on its own schedule, and the heartbeat sweep (see
/// `crates/slimm-server/src/voice/heartbeat.rs`) is a bounded backstop for
/// that, not an instant one, so a client relaunched moments after being
/// killed can poll this and still see the identity it just lost. Rendering
/// that back as "you are in this call" is exactly the bug filtering it out
/// here fixes; see `voice_roster_test.dart` and
/// `channel_rail_voice_roster_test.dart`.
///
/// A channel with no voice configured closes the stream on its first answer
/// rather than polling a server that will only ever say the same thing
/// again, which is why [AsyncLoading] is also what a text-only deployment
/// settles on forever. A transient failure - unreachable SFU, a blip in
/// authentication - adds nothing this tick and simply waits for the next
/// one, so the last roster this client actually saw stays on screen instead
/// of being cleared to looking empty.
///
/// `voice.activity` (`api.VoiceActivityChanged`) refreshes this promptly
/// rather than leaving a join or hangup to surface on the next poll tick, up
/// to [voiceRosterPollInterval] later. It names no participant - see the
/// event's own doc comment - so this is a nudge to re-ask, exactly what a
/// stray or duplicate frame already costs nothing extra to trigger.
final voiceRosterProvider = StreamProvider.autoDispose
    .family<List<api.VoiceRosterParticipant>, String>((ref, channelId) {
      final client = ref.watch(apiProvider);
      final controller = StreamController<List<api.VoiceRosterParticipant>>();

      Future<void> tick(Timer? self) async {
        try {
          final roster = await client.voiceRoster(channelId);
          final selfId = client.session.tokens?.userId;
          final visible = selfId == null
              ? roster
              : roster.where((p) => p.userId != selfId).toList(growable: false);
          if (!controller.isClosed) controller.add(visible);
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

      final liveSub = ref.read(liveEventsProvider).listen((event) {
        if (event case api.VoiceActivityChanged(
          channelId: final eventChannelId,
        ) when eventChannelId == channelId) {
          unawaited(tick(timer));
        }
      });

      ref.onDispose(() {
        timer.cancel();
        unawaited(liveSub.cancel());
        unawaited(controller.close());
      });

      return controller.stream;
    });
