// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A message somebody kept for themselves. Split out of `models.dart` for the
/// line budget and re-exported there, as every `models_*` file is.
library;

import 'models.dart';

/// One entry in the caller's own saved list.
///
/// The private counterpart to [PinnedMessage]: a pin is a property of a
/// channel that everyone in it sees, this is a property of one account that
/// nobody else can read. There is no `savedBy`, because the only account a
/// saved list is ever served for is the one asking.
class SavedMessage {
  const SavedMessage({required this.message, required this.savedAt});

  final Message message;

  /// When the caller saved it, unix milliseconds - not when it was sent,
  /// which is [Message.createdAt]. The list is ordered by this, so keeping an
  /// old message puts it at the top rather than the bottom.
  final int savedAt;

  factory SavedMessage.fromJson(Map<String, dynamic> json) => SavedMessage(
        message: Message.fromJson(json),
        savedAt: json['saved_at'] as int,
      );
}
