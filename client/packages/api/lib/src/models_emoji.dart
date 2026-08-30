// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Custom emoji: the deployment's own named images, typed between colons.
///
/// Split out of models.dart purely to stay under this repo's line budget; see
/// that file for how the pieces are recombined into one import.
library;

/// One of the deployment's own emoji.
///
/// The image is not carried here: it is fetched separately through
/// [SlimmApiEmoji.fetchCustomEmojiImage], the same way an attachment's or an
/// avatar's bytes are, because the bytes are content-addressed and far larger
/// than the metadata a list needs.
class CustomEmoji {
  const CustomEmoji({
    required this.id,
    required this.name,
    required this.uploaderId,
    required this.createdAt,
  });

  final String id;

  /// Lowercase a-z, 0-9 and underscore, normalised by the server on upload.
  /// It is what a member types between colons, without the colons.
  final String name;

  /// Who uploaded it. Null once that account has been deleted, exactly as
  /// [Message.authorId] is.
  final String? uploaderId;

  /// When it was added, unix milliseconds.
  final int createdAt;

  /// The Slack-convention shortcode a member types for this emoji.
  ///
  /// Kept here rather than at each render site so the one place that decides
  /// the delimiters is the one place a parser has to agree with.
  String get shortcode => ':$name:';

  factory CustomEmoji.fromJson(Map<String, dynamic> json) => CustomEmoji(
        id: json['id'] as String,
        name: json['name'] as String,
        uploaderId: json['uploader_id'] as String?,
        createdAt: json['created_at'] as int,
      );
}

/// One image [SlimmApiEmoji.bulkUploadCustomEmoji] queues in a single
/// request: the raw bytes and the requested name, mirroring the single
/// [SlimmApiEmoji.uploadCustomEmoji]'s own two inputs.
class EmojiBulkImage {
  const EmojiBulkImage({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;
}
