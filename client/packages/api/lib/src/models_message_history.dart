// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// A message's edit history: the versions it has held, as returned by
/// `SlimmApi.getMessageHistory`.
library;

/// One version a message has held.
///
/// [at] is when this version became the message's content: the message's own
/// creation time for the original, and the moment of the edit that produced
/// each later one. A history list is oldest first and its last element is
/// always the current content.
class MessageRevision {
  const MessageRevision({required this.content, required this.at});

  final String content;
  final int at;

  factory MessageRevision.fromJson(Map<String, dynamic> json) =>
      MessageRevision(
        content: json['content'] as String,
        at: json['at'] as int,
      );
}
