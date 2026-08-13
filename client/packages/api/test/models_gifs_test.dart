// SPDX-License-Identifier: Apache-2.0
library;

import 'package:slimm_api/api.dart';
import 'package:test/test.dart';

void main() {
  test('GifResult.fromJson reads every field', () {
    final result = GifResult.fromJson({
      'id': 'a-token',
      'title': 'a cat waving',
      'width': 498,
      'height': 373,
    });
    expect(result.id, 'a-token');
    expect(result.title, 'a cat waving');
    expect(result.width, 498);
    expect(result.height, 373);
  });

  test('a provider that never carried dimensions reads as zero', () {
    final result = GifResult.fromJson({
      'id': 'a-token',
      'title': '',
      'width': 0,
      'height': 0,
    });
    expect(result.width, 0);
    expect(result.height, 0);
  });
}
