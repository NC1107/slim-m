#ifndef RUNNER_NOW_PLAYING_SMTC_H_
#define RUNNER_NOW_PLAYING_SMTC_H_

#include <optional>
#include <string>

// What the system media transport controls (SMTC) say is playing.
struct NowPlayingTrack {
  std::wstring title;
  std::wstring artist;
};

// The playing session's track from the last background read, or nothing.
//
// The first call starts a worker that reads SMTC every two seconds, and the
// worker stops by itself once nobody has asked for fifteen seconds. Nothing is
// read before the first call or after the asking stops, so a switched-off
// source costs nothing. Never blocks the caller.
std::optional<NowPlayingTrack> CurrentNowPlaying();

#endif  // RUNNER_NOW_PLAYING_SMTC_H_
