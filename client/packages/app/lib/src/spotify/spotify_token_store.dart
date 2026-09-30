// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Where the Spotify tokens live: this device's key store, never the
/// server, so slim-m's server holds no third-party credential (decision 0044).
library;

import 'dart:convert';

import 'package:slimm_platform/platform.dart';

import 'spotify_client.dart';

const spotifyTokensHandle = 'slimm.spotify.tokens';

class SpotifyTokenStore {
  SpotifyTokenStore(this._keys);

  final KeyStore _keys;

  Future<SpotifyTokens?> load() async {
    final raw = await _keys.read(spotifyTokensHandle);
    if (raw == null) return null;
    try {
      return SpotifyTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      await clear();
      return null;
    }
  }

  Future<void> save(SpotifyTokens tokens) =>
      _keys.put(spotifyTokensHandle, jsonEncode(tokens.toJson()));

  Future<void> clear() => _keys.delete(spotifyTokensHandle);
}
