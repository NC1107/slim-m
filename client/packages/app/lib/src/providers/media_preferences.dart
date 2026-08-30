// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Two local media performance preferences that gate how much an inline
/// attachment does on its own before you ask.
///
/// [MediaAutoDownload] decides whether an image fetches the moment it scrolls
/// into view or waits to be tapped - the data lever, for a metered connection.
/// [GifAutoplay] decides whether a gif animates on its own or holds on its
/// first frame until tapped - the battery-and-CPU lever, since animating gifs
/// decode every frame forever. Both default to what this app has always done,
/// so leaving them alone changes nothing. Opening an attachment always shows it
/// fully regardless.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Whether an inline image downloads on sight or waits for a tap.
enum MediaAutoDownload { always, manual }

/// Whether a gif animates on its own or waits for a tap.
enum GifAutoplay { autoplay, tapToPlay }

extension MediaAutoDownloadX on MediaAutoDownload {
  String get label => switch (this) {
    MediaAutoDownload.always => 'Always (default)',
    MediaAutoDownload.manual => 'Only when I tap',
  };
}

extension GifAutoplayX on GifAutoplay {
  String get label => switch (this) {
    GifAutoplay.autoplay => 'On (default)',
    GifAutoplay.tapToPlay => 'Tap to play',
  };
}

const mediaAutoDownloadKey = 'slimm.performance.media_autodownload';
const gifAutoplayKey = 'slimm.performance.gif_autoplay';

const defaultMediaAutoDownload = MediaAutoDownload.always;
const defaultGifAutoplay = GifAutoplay.autoplay;

class MediaAutoDownloadController extends StateNotifier<MediaAutoDownload> {
  MediaAutoDownloadController(this._ref) : super(defaultMediaAutoDownload);

  final Ref _ref;

  Future<void> restore() async {
    try {
      final prefs = await _ref.read(preferencesProvider.future);
      final stored = prefs.getString(mediaAutoDownloadKey);
      for (final value in MediaAutoDownload.values) {
        if (value.name == stored) {
          state = value;
          return;
        }
      }
    } catch (_) {
      // Not worth failing a launch over; the default always downloads.
    }
  }

  Future<void> select(MediaAutoDownload value) async {
    state = value;
    final prefs = await _ref.read(preferencesProvider.future);
    await prefs.setString(mediaAutoDownloadKey, value.name);
  }
}

class GifAutoplayController extends StateNotifier<GifAutoplay> {
  GifAutoplayController(this._ref) : super(defaultGifAutoplay);

  final Ref _ref;

  Future<void> restore() async {
    try {
      final prefs = await _ref.read(preferencesProvider.future);
      final stored = prefs.getString(gifAutoplayKey);
      for (final value in GifAutoplay.values) {
        if (value.name == stored) {
          state = value;
          return;
        }
      }
    } catch (_) {
      // Not worth failing a launch over; the default autoplays.
    }
  }

  Future<void> select(GifAutoplay value) async {
    state = value;
    final prefs = await _ref.read(preferencesProvider.future);
    await prefs.setString(gifAutoplayKey, value.name);
  }
}

final mediaAutoDownloadControllerProvider =
    StateNotifierProvider<MediaAutoDownloadController, MediaAutoDownload>(
      MediaAutoDownloadController.new,
    );

final gifAutoplayControllerProvider =
    StateNotifierProvider<GifAutoplayController, GifAutoplay>(
      GifAutoplayController.new,
    );
