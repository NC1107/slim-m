// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Checks GitHub for a newer client release during the splash, so the startup
/// screen can offer it. Phase 1 of decision 0020: this only ever reports what
/// it found, with a format-appropriate action the UI turns into a link or a
/// package-manager hint - nothing is downloaded or executed here.
///
/// Best-effort by construction: a network failure, a timeout, a rate-limit,
/// or any unexpected shape resolves to `null` (no update to offer), never an
/// error and never a block on startup.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:slimm_platform/platform.dart';

/// The repository whose `client-v*` releases this build updates from.
const _repo = 'NC1107/slim-m';

/// Whether the update check is switched off by `SLIMM_NO_UPDATE_CHECK`. Honors
/// AppImage's golden rule that an app respect a "do not check for updates"
/// flag - a system may manage updates centrally - and lets the desktop-shell
/// smoke and any offline CI run the real startup path without the check ever
/// reaching out or, worse, blocking on a prompt with no one to answer it.
bool updateChecksDisabled() {
  if (kIsWeb) return false;
  final flag = Platform.environment['SLIMM_NO_UPDATE_CHECK'];
  return flag != null &&
      flag.isNotEmpty &&
      flag != '0' &&
      flag.toLowerCase() != 'false';
}

/// How long the release check may take before startup gives up and launches
/// the current client regardless.
const _timeout = Duration(seconds: 4);

/// A newer client release than the one running, and how this install can get
/// it.
class ClientUpdate {
  const ClientUpdate({
    required this.version,
    required this.releaseUrl,
    required this.format,
  });

  /// The newer version, without the `client-v` tag prefix (for example
  /// `0.70.0`).
  final String version;

  /// The release's GitHub page, where every format's artifacts are attached.
  final String releaseUrl;

  /// How this build was installed, which decides the action the UI offers.
  final InstallFormat format;
}

/// The latest `client-v*` release newer than [currentVersion], or `null` when
/// there is none, the check failed, or this is not a self-updatable desktop
/// build's concern. [client] and [format] are injectable for tests.
Future<ClientUpdate?> checkForClientUpdate({
  required String currentVersion,
  http.Client? client,
  InstallFormat? format,
}) async {
  final installFormat = format ?? currentInstallFormat();
  if (installFormat == InstallFormat.unknown) return null;

  final owned = client ?? http.Client();
  try {
    final response = await owned
        .get(
          Uri.parse('https://api.github.com/repos/$_repo/releases?per_page=30'),
          headers: const {'Accept': 'application/vnd.github+json'},
        )
        .timeout(_timeout);
    if (response.statusCode != 200) return null;
    final releases = jsonDecode(response.body);
    if (releases is! List) return null;

    String? bestVersion;
    String? bestUrl;
    for (final entry in releases) {
      if (entry is! Map<String, dynamic>) continue;
      if (entry['draft'] == true || entry['prerelease'] == true) continue;
      final tag = entry['tag_name'];
      if (tag is! String || !tag.startsWith('client-v')) continue;
      final version = tag.substring('client-v'.length);
      if (parseVersion(version) == null) continue;
      if (bestVersion == null || isNewer(version, bestVersion)) {
        bestVersion = version;
        bestUrl = entry['html_url'] as String?;
      }
    }

    if (bestVersion == null || bestUrl == null) return null;
    if (!isNewer(bestVersion, currentVersion)) return null;
    return ClientUpdate(
      version: bestVersion,
      releaseUrl: bestUrl,
      format: installFormat,
    );
  } catch (_) {
    return null;
  } finally {
    if (client == null) owned.close();
  }
}

/// `[major, minor, patch]` from a `X.Y.Z` string, or `null` if it is not that
/// shape. Any pre-release or build suffix after the patch is ignored.
List<int>? parseVersion(String raw) {
  final core = raw.split(RegExp('[-+]')).first;
  final parts = core.split('.');
  if (parts.length != 3) return null;
  final numbers = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null) return null;
    numbers.add(n);
  }
  return numbers;
}

/// Whether [candidate] is a strictly higher version than [against]. A version
/// that will not parse is treated as not-newer, so junk never offers itself
/// as an update.
bool isNewer(String candidate, String against) {
  final a = parseVersion(candidate);
  final b = parseVersion(against);
  if (a == null) return false;
  if (b == null) return true;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}
