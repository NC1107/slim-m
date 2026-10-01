// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// An artifact the manifest lists is only kept when it is fetchable over https
/// and its sha256 is a lowercase 64-digit hex string.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:slimm_app/src/desktop/self_update/update_manifest.dart';

final _goodSha = 'ab' * 32;

UpdateManifest _manifestWith({String? url, String? sha256}) {
  final artifact = {
    'url': url ?? 'https://example.com/slim-m-client.tar.gz',
    'sha256': sha256 ?? _goodSha,
    'size': 4096,
  };
  return parseManifest(
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'schema': supportedManifestSchema,
          'version': '0.90.0',
          'tag': 'client-v0.90.0',
          'artifacts': {'linux-x64': artifact},
        }),
      ),
    ),
  );
}

void main() {
  test('a well-formed https artifact is kept', () {
    expect(_manifestWith().artifacts.keys, ['linux-x64']);
  });

  test('an http artifact url is dropped', () {
    final manifest = _manifestWith(url: 'http://example.com/client.tar.gz');
    expect(manifest.artifacts, isEmpty);
  });

  test('a non-hex sha256 drops the artifact', () {
    expect(_manifestWith(sha256: 'zz' * 32).artifacts, isEmpty);
  });

  test('a sha256 of the wrong length drops the artifact', () {
    expect(_manifestWith(sha256: 'ab' * 31).artifacts, isEmpty);
  });

  test('an uppercase sha256 drops the artifact', () {
    expect(_manifestWith(sha256: 'AB' * 32).artifacts, isEmpty);
  });
}
