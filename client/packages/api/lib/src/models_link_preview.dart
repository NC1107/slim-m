// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The result of `SlimmApiLinkPreview.fetchLinkPreview`.
library;

/// A recognized playable video provider a link preview can carry. Only
/// [youtube] exists today; unknown values from a future server decode to
/// null on this client rather than throwing, the same forward-compatibility
/// [LinkPreview.fromJson] already gives every other field.
enum LinkPreviewVideoProvider {
  youtube;

  static LinkPreviewVideoProvider? fromWire(String? value) => switch (value) {
        'youtube' => youtube,
        _ => null,
      };
}

/// A pasted URL's unfurled OpenGraph/title metadata. [imageToken] is an
/// opaque token minted by the server, redeemable at `fetchLinkPreviewImage`
/// - never the upstream image URL, so nothing about displaying a preview
/// ever reaches the linked site directly.
///
/// [videoProvider]/[videoId] are set together when the server recognized the
/// linked page as a playable video (YouTube today): a caller renders a
/// click-to-play affordance instead of the static card, and must not contact
/// the provider until the reader taps - see `link_preview_card.dart`.
class LinkPreview {
  const LinkPreview({
    required this.url,
    this.title,
    this.description,
    this.siteName,
    this.imageToken,
    this.videoProvider,
    this.videoId,
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

  /// Which known provider the linked page's video is, if any. Null for an
  /// ordinary link.
  final LinkPreviewVideoProvider? videoProvider;

  /// The provider's own canonical video id, paired with [videoProvider] -
  /// never a URL, so a caller builds its own playback URL from the two.
  final String? videoId;

  /// Whether this preview should render as click-to-play rather than a
  /// static card.
  bool get isPlayableVideo => videoProvider != null && videoId != null;

  factory LinkPreview.fromJson(Map<String, dynamic> json) => LinkPreview(
        url: json['url'] as String,
        title: json['title'] as String?,
        description: json['description'] as String?,
        siteName: json['site_name'] as String?,
        imageToken: json['image_token'] as String?,
        videoProvider: LinkPreviewVideoProvider.fromWire(
          json['video_provider'] as String?,
        ),
        videoId: json['video_id'] as String?,
      );

  /// The `youtube-nocookie.com` embed URL for inline web playback - no
  /// cookies set until the reader taps and this actually loads. Null unless
  /// [isPlayableVideo]. Desktop and mobile do not use this: they open [url]
  /// (the pasted link itself) in the system browser instead, since Flutter
  /// has no iframe host off the web engine.
  Uri? get embedUrl {
    final id = videoId;
    if (videoProvider != LinkPreviewVideoProvider.youtube || id == null) {
      return null;
    }
    return Uri.https('www.youtube-nocookie.com', '/embed/$id', {
      'autoplay': '1',
    });
  }
}
