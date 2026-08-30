// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Direct-message conversations: the `dms` tag.
///
/// Split out of models.dart purely to stay under this repo's line budget; see
/// that file for how the pieces are recombined into one import.
library;

import 'models_users.dart';

/// One of the caller's DM conversations: a channel like any other for
/// messages, search, and sync, plus the other participant and the caller's
/// own unread count in it.
class DmConversation {
  const DmConversation({
    required this.channelId,
    required this.user,
    required this.unread,
    required this.createdAt,
  });

  final String channelId;
  final UserProfile user;
  final int unread;

  /// Unix milliseconds the DM channel was first opened.
  final int createdAt;

  factory DmConversation.fromJson(Map<String, dynamic> json) => DmConversation(
        channelId: json['channel_id'] as String,
        user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
        unread: json['unread'] as int,
        createdAt: json['created_at'] as int,
      );
}
