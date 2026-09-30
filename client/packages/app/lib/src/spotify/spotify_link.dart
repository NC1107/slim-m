// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Linking and unlinking a Spotify account from the one Settings switch
/// (decision 0044).
///
/// The switch is the link: turning it on sends the person to Spotify and
/// only lands on when they approve, turning it off deletes the token stored
/// on this device. Spotify has no revoke call, so the description tells the
/// person where to remove slim-m on Spotify's side too.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:slimm_platform/platform.dart';
import 'package:url_launcher/url_launcher.dart';

import '../deep_links.dart';
import '../providers/activity_sharing_settings.dart';
import '../providers/providers.dart';
import 'spotify_client.dart';
import 'spotify_config.dart';
import 'spotify_pkce.dart';
import 'spotify_source.dart';
import 'spotify_token_store.dart';

const shareSpotifyKey = 'slimm.presence.share_spotify';
const _linkTimeout = Duration(minutes: 5);

final spotifyTokenStoreProvider = Provider<SpotifyTokenStore>(
  (ref) => SpotifyTokenStore(ref.read(keyStoreProvider)),
);

final spotifyClientProvider = Provider<SpotifyClient>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return SpotifyClient(
    client: client,
    clientId: ref.read(spotifyClientIdProvider),
  );
});

final spotifySourceProvider = Provider<NowPlayingSource>(
  (ref) => SpotifyNowPlayingSource(
    client: ref.read(spotifyClientProvider),
    store: ref.read(spotifyTokenStoreProvider),
  ),
);

/// Opens Spotify's consent page in the browser. Overridden in tests.
final spotifyLauncherProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// Why the last link attempt did not finish, shown in Settings until
/// dismissed. Null when there is nothing to report.
final spotifyLinkErrorProvider = StateProvider<String?>((ref) => null);

class SpotifyLinker {
  SpotifyLinker(this._ref);

  final Ref _ref;

  /// True once tokens are stored; false, with the reason in
  /// [spotifyLinkErrorProvider], when anything stopped it.
  Future<bool> link() async {
    final error = _ref.read(spotifyLinkErrorProvider.notifier);
    error.state = null;
    final clientId = _ref.read(spotifyClientIdProvider);
    if (clientId.isEmpty) return false;
    final verifier = randomUrlSafe();
    final state = randomUrlSafe(32);
    final callback = _waitForCallback(state);
    final opened = await _ref.read(spotifyLauncherProvider)(
      spotifyAuthorizeUri(
        clientId: clientId,
        challenge: await codeChallenge(verifier),
        state: state,
      ),
    );
    if (!opened) {
      unawaited(callback.catchError((_) => ''));
      error.state = 'Could not open the browser to sign in to Spotify.';
      return false;
    }
    try {
      final code = await callback;
      final tokens = await _ref
          .read(spotifyClientProvider)
          .exchangeCode(code, verifier);
      await _ref.read(spotifyTokenStoreProvider).save(tokens);
      return true;
    } on TimeoutException {
      error.state = 'Spotify sign-in timed out. Try again.';
    } on SpotifyAuthException catch (e) {
      error.state = 'Spotify did not link: ${e.message}.';
    } on http.ClientException {
      error.state = 'Could not reach Spotify. Check the connection and retry.';
    }
    return false;
  }

  Future<void> unlink() => _ref.read(spotifyTokenStoreProvider).clear();

  /// The authorization code from the redirect that carries [state].
  Future<String> _waitForCallback(String state) async {
    final uris = _ref.read(deepLinkUrisProvider);
    final uri = await uris
        .firstWhere(
          (uri) => uri.scheme == 'slimm' && uri.host == 'spotify-callback',
        )
        .timeout(_linkTimeout);
    final code = uri.queryParameters['code'];
    if (uri.queryParameters['state'] != state || code == null) {
      throw const SpotifyAuthException('sign-in was cancelled or refused');
    }
    return code;
  }
}

final spotifyLinkerProvider = Provider<SpotifyLinker>(SpotifyLinker.new);

class SpotifySwitchController extends ActivitySwitchController {
  SpotifySwitchController(this._ref) : super(_ref, shareSpotifyKey);

  final Ref _ref;

  @override
  Future<void> setEnabled(bool enabled) async {
    final linker = _ref.read(spotifyLinkerProvider);
    if (enabled) {
      if (!await linker.link()) return;
    } else {
      await linker.unlink();
    }
    await super.setEnabled(enabled);
  }
}

final shareSpotifyProvider =
    StateNotifierProvider<SpotifySwitchController, bool>(
      SpotifySwitchController.new,
    );
