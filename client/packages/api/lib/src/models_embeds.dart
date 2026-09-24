// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Embeds: structured content a webhook or a bot attaches to a message.
library;

/// A caller's colour, already reduced to one of a closed set of swatches -
/// never a raw hex. Unrecognised values (a future server) read as null.
enum EmbedAccent {
  red,
  orange,
  yellow,
  green,
  blue,
  purple;

  static EmbedAccent? fromWire(String? value) => switch (value) {
        'red' => red,
        'orange' => orange,
        'yellow' => yellow,
        'green' => green,
        'blue' => blue,
        'purple' => purple,
        _ => null,
      };
}

/// One field on an [Embed] - a name/value pair, optionally laid out inline
/// with its neighbors.
class EmbedField {
  const EmbedField({
    required this.name,
    required this.value,
    required this.inline,
  });

  final String name;
  final String value;
  final bool inline;

  factory EmbedField.fromJson(Map<String, dynamic> json) => EmbedField(
        name: json['name'] as String,
        value: json['value'] as String,
        inline: json['inline'] as bool,
      );
}

/// Structured content a webhook or a bot attached to a message, fixed once
/// the message exists - see `docs/decisions/0030-incoming-webhooks.md`.
class Embed {
  const Embed({
    this.title,
    this.description,
    this.url,
    this.accent,
    this.authorName,
    this.authorUrl,
    this.fields = const [],
    this.footerText,
    this.timestamp,
    this.imageToken,
    this.thumbnailToken,
  });

  final String? title;
  final String? description;
  final String? url;
  final EmbedAccent? accent;
  final String? authorName;
  final String? authorUrl;
  final List<EmbedField> fields;
  final String? footerText;
  final int? timestamp;

  /// Redeemable at `fetchLinkPreviewImage`, the same proxy a pasted link's
  /// preview image already uses - never the raw upstream URL.
  final String? imageToken;
  final String? thumbnailToken;

  factory Embed.fromJson(Map<String, dynamic> json) => Embed(
        title: json['title'] as String?,
        description: json['description'] as String?,
        url: json['url'] as String?,
        accent: EmbedAccent.fromWire(json['accent'] as String?),
        authorName: json['author_name'] as String?,
        authorUrl: json['author_url'] as String?,
        fields: (json['fields'] as List<dynamic>?)
                ?.map((f) => EmbedField.fromJson(f as Map<String, dynamic>))
                .toList(growable: false) ??
            const [],
        footerText: json['footer_text'] as String?,
        timestamp: json['timestamp'] as int?,
        imageToken: json['image_token'] as String?,
        thumbnailToken: json['thumbnail_token'] as String?,
      );
}
