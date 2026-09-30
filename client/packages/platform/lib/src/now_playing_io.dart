// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Picks the now-playing source for the OS this `dart:io` build runs on.
library;

import 'dart:io' show Platform;

import 'now_playing.dart';
import 'now_playing_channel.dart';
import 'now_playing_mpris.dart';

/// The platform is a parameter so a test on Linux can still take the Windows
/// branch; nothing but the real callers ever passes it.
NowPlayingSource? createNowPlayingSource({
  bool? linux,
  bool? windows,
}) {
  if (linux ?? Platform.isLinux) return MprisNowPlayingSource();
  if (windows ?? Platform.isWindows) return ChannelNowPlayingSource();
  return null;
}
