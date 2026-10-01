// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The per-channel read markers `GET /read-states` answers in one call.
///
/// Split out of models.dart to stay under this repo's line budget.
library;

import 'models.dart';

/// One channel's [ReadState], as `GET /read-states` lists it for every
/// channel the caller can read.
class ChannelReadState {
  const ChannelReadState({required this.channelId, required this.state});

  final String channelId;
  final ReadState state;

  factory ChannelReadState.fromJson(Map<String, dynamic> json) =>
      ChannelReadState(
        channelId: json['channel_id'] as String,
        state: ReadState.fromJson(json),
      );
}
