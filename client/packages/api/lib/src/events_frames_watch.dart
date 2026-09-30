// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
part of 'events.dart';

/// The room's watch position, about every 5 seconds and on every play,
/// pause or seek. Ephemeral: a missed one is corrected by the next, and
/// silence is the end of the session. The durable copy is
/// `GET /channels/{channelId}/watch-session`. See
/// docs/decisions/0050-watch-party-sync-authority-and-direct-play.md.
class WatchTick extends ServerEvent {
  const WatchTick({
    required this.channelId,
    required this.itemId,
    required this.playing,
    required this.positionMs,
    required this.sampledAtMs,
    required this.epoch,
  });

  final String channelId;
  final String itemId;
  final bool playing;
  final int positionMs;

  /// The server clock at the sample; a receiver times it by its own arrival.
  final int sampledAtMs;

  /// Changes on every seek or title change.
  final int epoch;
}
