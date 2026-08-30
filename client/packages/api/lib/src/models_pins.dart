// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Pinned messages: every [Message] field, flattened, plus when and by whom.
///
/// Split out of models.dart purely to stay under this repo's line budget; see
/// that file for how the pieces are recombined into one import.
library;

import 'models.dart';

/// A pinned message. The wire shape flattens every [Message] field alongside
/// [pinnedAt]/[pinnedBy] rather than nesting the message, so parsing reads
/// the same json twice: once as a [Message], once for the pin metadata.
class PinnedMessage {
  const PinnedMessage({
    required this.message,
    required this.pinnedAt,
    required this.pinnedBy,
  });

  final Message message;

  /// When the message was pinned, unix milliseconds.
  final int pinnedAt;

  /// Who pinned it. Null once that account has been anonymized, exactly as
  /// [Message.authorId] is.
  final String? pinnedBy;

  factory PinnedMessage.fromJson(Map<String, dynamic> json) => PinnedMessage(
        message: Message.fromJson(json),
        pinnedAt: json['pinned_at'] as int,
        pinnedBy: json['pinned_by'] as String?,
      );
}
