// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Where the room is in what it is watching, read from REST once and kept
/// current by the bot's `watch.tick` frames.
///
/// A tick is ephemeral, so a missed one is corrected by the next and a room
/// nobody has heard from in [watchRoomStaleAfter] is treated as over. A title
/// change or a seek shows up as a new epoch, which is the cue to re-read the
/// session rather than trust a frame that carries no title. See
/// docs/decisions/0050-watch-party-sync-authority-and-direct-play.md.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'live_events.dart';
import 'providers.dart';

/// Three missed ticks; the bot sends one about every 5 seconds.
const watchRoomStaleAfter = Duration(seconds: 15);

/// The app's wall clock, replaceable so a test can hold time still.
final watchClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// One sample of the room's position, timed by this device's own clock.
class WatchRoom {
  const WatchRoom({
    required this.itemId,
    required this.title,
    required this.playing,
    required this.position,
    required this.sampledAt,
    required this.epoch,
    this.duration,
    this.controllerUserId,
  });

  final String itemId;
  final String title;
  final bool playing;
  final Duration? duration;

  /// Where the room was at [sampledAt].
  final Duration position;
  final DateTime sampledAt;
  final int epoch;
  final String? controllerUserId;

  /// A session read over REST: its sample is [api.WatchSession.serverTimeMs]
  /// minus [api.WatchSession.sampledAtMs] old, worked out on the server's one
  /// clock so this device's skew never enters.
  factory WatchRoom.fromSession(api.WatchSession s, DateTime now) => WatchRoom(
    itemId: s.itemId,
    title: s.title,
    playing: s.playing,
    position: Duration(milliseconds: s.positionMs),
    sampledAt: now.subtract(
      Duration(milliseconds: s.serverTimeMs - s.sampledAtMs),
    ),
    epoch: s.epoch,
    duration: s.durationMs == null
        ? null
        : Duration(milliseconds: s.durationMs!),
    controllerUserId: s.controllerUserId,
  );

  /// A tick is taken as fresh on arrival; network latency is well inside the
  /// two seconds the room tolerates.
  WatchRoom afterTick(api.WatchTick tick, DateTime now) => WatchRoom(
    itemId: itemId,
    title: title,
    playing: tick.playing,
    position: Duration(milliseconds: tick.positionMs),
    sampledAt: now,
    epoch: tick.epoch,
    duration: duration,
    controllerUserId: controllerUserId,
  );

  Duration positionAt(DateTime now) {
    final elapsed = playing ? now.difference(sampledAt) : Duration.zero;
    final at = position + (elapsed.isNegative ? Duration.zero : elapsed);
    final end = duration;
    return end != null && at > end ? end : at;
  }

  bool isStale(DateTime now) => now.difference(sampledAt) > watchRoomStaleAfter;
}

/// The room's session for [channelId], or null while nothing is playing.
final watchRoomProvider = StreamProvider.autoDispose.family<WatchRoom?, String>((
  ref,
  channelId,
) {
  final client = ref.watch(apiProvider);
  final clock = ref.watch(watchClockProvider);
  final controller = StreamController<WatchRoom?>();
  WatchRoom? current;

  void emit(WatchRoom? room) {
    current = room;
    if (!controller.isClosed) controller.add(room);
  }

  Future<void> load() async {
    try {
      final session = await client.getWatchSession(channelId);
      emit(session == null ? null : WatchRoom.fromSession(session, clock()));
    } catch (_) {
      // A readout is best effort: a failure keeps what is on screen until the next tick.
    }
  }

  final sub = ref.read(liveEventsProvider).listen((event) {
    if (event is! api.WatchTick || event.channelId != channelId) return;
    final room = current;
    final moved =
        room == null ||
        room.itemId != event.itemId ||
        room.epoch != event.epoch;
    if (room != null) emit(room.afterTick(event, clock()));
    if (moved) unawaited(load());
  });
  ref.onDispose(() {
    unawaited(sub.cancel());
    unawaited(controller.close());
  });
  unawaited(load());
  return controller.stream;
});
