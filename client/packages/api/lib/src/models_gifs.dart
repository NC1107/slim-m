// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// One result from `SlimmApiGifs.searchGifs`.
library;

/// A single GIF search result. [id] is an opaque token minted by the
/// search, redeemable at `fetchGifPreview` and `selectGif` for a short
/// time - never the provider's own id or a raw CDN URL, so nothing about
/// displaying or picking a result ever reaches the provider directly.
class GifResult {
  const GifResult({
    required this.id,
    required this.title,
    required this.width,
    required this.height,
  });

  final String id;
  final String title;

  /// The full-resolution image's own dimensions, or `0` when the provider's
  /// response did not carry them - a grid cell falls back to a fixed aspect
  /// ratio for those rather than treating zero as a real answer.
  final int width;
  final int height;

  factory GifResult.fromJson(Map<String, dynamic> json) => GifResult(
        id: json['id'] as String,
        title: json['title'] as String,
        width: json['width'] as int,
        height: json['height'] as int,
      );
}
