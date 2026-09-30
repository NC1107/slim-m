// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The host side of game detection: process names and Steam's own record of
/// what it is running. Everything here is read on demand and only ever
/// matched against the allowlist by the caller.
library;

import 'dart:convert';
import 'dart:io';

import 'game_source.dart';

GameSource? createGameSource({bool? linux, bool? windows, bool? macos}) {
  final supported = (linux ?? Platform.isLinux) ||
      (windows ?? Platform.isWindows) ||
      (macos ?? Platform.isMacOS);
  return supported ? AllowlistGameSource(SystemGameProbe()) : null;
}

/// The app id in Steam's `registry.vdf`, or null when it is 0 or absent.
int? parseSteamVdfAppId(String vdf) {
  final match = RegExp(r'"RunningAppID"\s+"(\d+)"').firstMatch(vdf);
  final id = int.tryParse(match?.group(1) ?? '');
  return id == null || id == 0 ? null : id;
}

/// The DWORD in `reg query ... /v RunningAppID` output, or null.
int? parseSteamRegQuery(String output) {
  final match = RegExp(
    r'RunningAppID\s+REG_DWORD\s+0x([0-9a-fA-F]+)',
  ).firstMatch(output);
  final id = int.tryParse(match?.group(1) ?? '', radix: 16);
  return id == null || id == 0 ? null : id;
}

/// Image names from `tasklist /fo csv /nh`.
Iterable<String> parseTasklist(String output) sync* {
  for (final line in const LineSplitter().convert(output)) {
    final match = RegExp(r'^"([^"]+)"').firstMatch(line);
    if (match != null) yield match.group(1)!;
  }
}

class SystemGameProbe implements GameProbe {
  @override
  Future<Iterable<String>> runningProcessNames() async {
    if (Platform.isLinux) return _linuxProcesses();
    if (Platform.isWindows) {
      final result = await Process.run('tasklist', ['/fo', 'csv', '/nh']);
      return parseTasklist(result.stdout as String);
    }
    final result = await Process.run('ps', ['-axco', 'comm']);
    return const LineSplitter().convert(result.stdout as String);
  }

  Future<Iterable<String>> _linuxProcesses() async {
    final names = <String>[];
    await for (final entry in Directory('/proc').list()) {
      final pid = entry.path.split('/').last;
      if (int.tryParse(pid) == null) continue;
      try {
        names.add(await File('${entry.path}/comm').readAsString());
      } on FileSystemException {
        continue;
      }
    }
    return names;
  }

  @override
  Future<int?> runningSteamAppId() async {
    if (Platform.isWindows) {
      final result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Valve\Steam',
        '/v',
        'RunningAppID',
      ]);
      return parseSteamRegQuery(result.stdout as String);
    }
    final home = Platform.environment['HOME'];
    if (home == null) return null;
    final candidates = Platform.isMacOS
        ? ['$home/Library/Application Support/Steam/registry.vdf']
        : [
            '$home/.steam/registry.vdf',
            '$home/.var/app/com.valvesoftware.Steam/.steam/registry.vdf',
          ];
    for (final path in candidates) {
      final file = File(path);
      if (await file.exists()) {
        return parseSteamVdfAppId(await file.readAsString());
      }
    }
    return null;
  }
}
