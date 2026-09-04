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
  });
}
