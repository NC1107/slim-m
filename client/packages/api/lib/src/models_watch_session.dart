// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The room's watch session, from `GET /channels/{channelId}/watch-session`.
/// See docs/decisions/0050-watch-party-sync-authority-and-direct-play.md.
library;

class WatchSession {
  const WatchSession({
    required this.channelId,
    required this.botUserId,
    required this.itemId,
    required this.title,
    required this.playing,
    required this.positionMs,
    required this.sampledAtMs,
    required this.epoch,
    required this.serverTimeMs,
    this.durationMs,
    this.controllerUserId,
  });

  final String channelId;
  final String botUserId;
  final String itemId;
  final String title;
  final int? durationMs;
  final bool playing;

  /// Where the room was at [sampledAtMs], not where it is now.
  final int positionMs;
  final int sampledAtMs;

  /// Changes on every seek or title change.
  final int epoch;
  final String? controllerUserId;

  /// The server clock when this was read; [serverTimeMs] minus [sampledAtMs]
  /// is how stale the sample is, on one clock.
  final int serverTimeMs;

  factory WatchSession.fromJson(Map<String, dynamic> json) => WatchSession(
        channelId: json['channel_id'] as String,
        botUserId: json['bot_user_id'] as String,
        itemId: json['item_id'] as String,
        title: json['title'] as String,
        durationMs: json['duration_ms'] as int?,
        playing: json['playing'] as bool,
        positionMs: json['position_ms'] as int,
        sampledAtMs: json['sampled_at_ms'] as int,
        epoch: json['epoch'] as int,
        controllerUserId: json['controller_user_id'] as String?,
        serverTimeMs: json['server_time_ms'] as int,
      );
}
