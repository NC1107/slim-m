// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The result of `SlimmApiLinkPreview.fetchLinkPreview`.
library;

/// A pasted URL's unfurled OpenGraph/title metadata. [imageToken] is an
/// opaque token minted by the server, redeemable at `fetchLinkPreviewImage`
/// - never the upstream image URL, so nothing about displaying a preview
/// ever reaches the linked site directly.
class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.siteName,
    this.imageToken,
  });

  /// The URL this preview is for, echoed back so a caller can key its own
  /// cache.
  final String url;

  /// The page's OpenGraph or plain title, if any.
  final String? title;

  /// The page's OpenGraph or meta description, if any.
  final String? description;

  /// The page's OpenGraph site name, if any.
  final String? siteName;

  /// An opaque token for the preview image, redeemable at
  /// `fetchLinkPreviewImage`. Null when the page had no usable image.
  final String? imageToken;

  factory LinkPreview.fromJson(Map<String, dynamic> json) => LinkPreview(
        url: json['url'] as String,
        title: json['title'] as String?,
        description: json['description'] as String?,
        siteName: json['site_name'] as String?,
        imageToken: json['image_token'] as String?,
      );
}
