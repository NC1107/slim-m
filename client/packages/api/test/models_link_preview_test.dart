// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
library;

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  test('LinkPreview.fromJson reads every field', () {
    final preview = LinkPreview.fromJson({
      'url': 'https://example.com/article',
      'title': 'An article',
      'description': 'What the article is about.',
      'site_name': 'Example',
      'image_token': 'a-token',
    });
    expect(preview.url, 'https://example.com/article');
    expect(preview.title, 'An article');
    expect(preview.description, 'What the article is about.');
    expect(preview.siteName, 'Example');
    expect(preview.imageToken, 'a-token');
  });

  test('a page with no usable metadata reads every optional field as null', () {
    final preview = LinkPreview.fromJson({'url': 'https://example.com'});
    expect(preview.url, 'https://example.com');
    expect(preview.title, isNull);
    expect(preview.description, isNull);
    expect(preview.siteName, isNull);
    expect(preview.imageToken, isNull);
    expect(preview.videoProvider, isNull);
    expect(preview.videoId, isNull);
    expect(preview.isPlayableVideo, isFalse);
  });

  test('a recognized YouTube video reads as playable', () {
    final preview = LinkPreview.fromJson({
      'url': 'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'video_provider': 'youtube',
      'video_id': 'dQw4w9WgXcQ',
    });
    expect(preview.videoProvider, LinkPreviewVideoProvider.youtube);
    expect(preview.videoId, 'dQw4w9WgXcQ');
    expect(preview.isPlayableVideo, isTrue);
  });

  test('an unknown future provider decodes to null rather than throwing', () {
    final preview = LinkPreview.fromJson({
      'url': 'https://example.com/video',
      'video_provider': 'vimeo',
      'video_id': '12345',
    });
    expect(preview.videoProvider, isNull);
    expect(preview.isPlayableVideo, isFalse);
  });

  test('embedUrl builds a youtube-nocookie autoplay URL', () {
    final preview = LinkPreview.fromJson({
      'url': 'https://youtu.be/dQw4w9WgXcQ',
      'video_provider': 'youtube',
      'video_id': 'dQw4w9WgXcQ',
    });
    expect(
      preview.embedUrl.toString(),
      'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?autoplay=1',
    );
  });

  test('embedUrl is null for a non-video preview', () {
    final preview = LinkPreview.fromJson({'url': 'https://example.com'});
    expect(preview.embedUrl, isNull);
  });
}
