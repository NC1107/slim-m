// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The three Spotify calls linking needs: trade a code for tokens, refresh
/// them, and read what is playing. Nothing else is ever requested, and no
/// cover art URL is read (decision 0044).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'spotify_config.dart';

class SpotifyTokens {
  const SpotifyTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
  });

  factory SpotifyTokens.fromJson(Map<String, dynamic> json) => SpotifyTokens(
    accessToken: json['access'] as String,
    refreshToken: json['refresh'] as String,
    expiresAt: DateTime.fromMillisecondsSinceEpoch(json['expires'] as int),
  );

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;

  Map<String, dynamic> toJson() => {
    'access': accessToken,
    'refresh': refreshToken,
    'expires': expiresAt.millisecondsSinceEpoch,
  };

  bool expiresWithin(Duration margin, DateTime now) =>
      !now.add(margin).isBefore(expiresAt);
}

sealed class SpotifyPlayback {
  const SpotifyPlayback();
}

class SpotifyPlaying extends SpotifyPlayback {
  const SpotifyPlaying({required this.title, this.artist});

  final String title;
  final String? artist;
}

/// Nothing playing, paused, an ad or a podcast episode.
class SpotifyIdle extends SpotifyPlayback {
  const SpotifyIdle();
}

class SpotifyRateLimited extends SpotifyPlayback {
  const SpotifyRateLimited(this.retryAfter);

  final Duration retryAfter;
}

class SpotifyUnauthorized extends SpotifyPlayback {
  const SpotifyUnauthorized();
}

/// The grant is gone: revoked on Spotify's side, or the code was refused.
class SpotifyAuthException implements Exception {
  const SpotifyAuthException(this.message);

  final String message;

  @override
  String toString() => 'SpotifyAuthException: $message';
}

class SpotifyClient {
  SpotifyClient({
    required http.Client client,
    required String clientId,
    DateTime Function()? now,
  }) : _http = client,
       _clientId = clientId,
       _now = now ?? DateTime.now;

  final http.Client _http;
  final String _clientId;
  final DateTime Function() _now;

  static final _tokenUri = Uri.https('accounts.spotify.com', '/api/token');
  static final _playingUri = Uri.https(
    'api.spotify.com',
    '/v1/me/player/currently-playing',
  );

  Future<SpotifyTokens> exchangeCode(String code, String verifier) => _token({
    'grant_type': 'authorization_code',
    'code': code,
    'redirect_uri': spotifyRedirectUri,
    'code_verifier': verifier,
  }, previousRefresh: null);

  Future<SpotifyTokens> refresh(String refreshToken) => _token({
    'grant_type': 'refresh_token',
    'refresh_token': refreshToken,
  }, previousRefresh: refreshToken);

  Future<SpotifyTokens> _token(
    Map<String, String> form, {
    required String? previousRefresh,
  }) async {
    final response = await _http.post(
      _tokenUri,
      body: {...form, 'client_id': _clientId},
    );
    if (response.statusCode == 400 || response.statusCode == 401) {
      throw const SpotifyAuthException('spotify refused the request');
    }
    if (response.statusCode != 200) {
      throw http.ClientException('token endpoint ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final refresh = json['refresh_token'] as String? ?? previousRefresh;
    if (refresh == null) {
      throw const SpotifyAuthException('no refresh token returned');
    }
    return SpotifyTokens(
      accessToken: json['access_token'] as String,
      refreshToken: refresh,
      expiresAt: _now().add(Duration(seconds: json['expires_in'] as int)),
    );
  }

  Future<SpotifyPlayback> currentlyPlaying(String accessToken) async {
    final response = await _http.get(
      _playingUri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    switch (response.statusCode) {
      case 200:
        return _parsePlayback(response.body);
      case 401:
        return const SpotifyUnauthorized();
      case 429:
        final seconds = int.tryParse(response.headers['retry-after'] ?? '');
        return SpotifyRateLimited(Duration(seconds: seconds ?? 30));
      case 204:
        return const SpotifyIdle();
      default:
        throw http.ClientException('player ${response.statusCode}');
    }
  }

  SpotifyPlayback _parsePlayback(String body) {
    final json = jsonDecode(body);
    if (json is! Map<String, dynamic> || json['is_playing'] != true) {
      return const SpotifyIdle();
    }
    final item = json['item'];
    if (json['currently_playing_type'] != 'track' ||
        item is! Map<String, dynamic>) {
      return const SpotifyIdle();
    }
    final title = item['name'];
    if (title is! String || title.trim().isEmpty) return const SpotifyIdle();
    final artists = item['artists'];
    final names = artists is List
        ? [
            for (final artist in artists)
              if (artist is Map && artist['name'] is String)
                (artist['name'] as String).trim(),
          ].where((name) => name.isNotEmpty).join(', ')
        : '';
    return SpotifyPlaying(
      title: title.trim(),
      artist: names.isEmpty ? null : names,
    );
  }
}
