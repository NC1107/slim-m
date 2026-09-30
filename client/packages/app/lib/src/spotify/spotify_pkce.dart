// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The PKCE half of Spotify's authorization-code flow, so no client secret
/// ever exists on a device.
library;

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'spotify_config.dart';

const _unreserved =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// A high-entropy random string, used for both the verifier and the state.
String randomUrlSafe([int length = 64, Random? random]) {
  final source = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < length; i++)
      _unreserved.codeUnitAt(source.nextInt(_unreserved.length)),
  ]);
}

/// S256 challenge: base64url of the SHA-256 of the verifier, unpadded.
Future<String> codeChallenge(String verifier) async {
  final hash = await Sha256().hash(utf8.encode(verifier));
  return base64Url.encode(hash.bytes).replaceAll('=', '');
}

Uri spotifyAuthorizeUri({
  required String clientId,
  required String challenge,
  required String state,
}) => Uri.https('accounts.spotify.com', '/authorize', {
  'response_type': 'code',
  'client_id': clientId,
  'scope': spotifyScope,
  'redirect_uri': spotifyRedirectUri,
  'code_challenge_method': 'S256',
  'code_challenge': challenge,
  'state': state,
  'show_dialog': 'true',
});
