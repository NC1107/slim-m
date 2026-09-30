#include "now_playing_smtc.h"

#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>

#include <chrono>
#include <mutex>
#include <thread>

namespace {

using winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSessionManager;
using winrt::Windows::Media::Control::
    GlobalSystemMediaTransportControlsSessionPlaybackStatus;

constexpr auto kReadInterval = std::chrono::seconds(2);
constexpr auto kIdleAfter = std::chrono::seconds(15);

std::mutex g_mutex;
std::optional<NowPlayingTrack> g_track;
std::chrono::steady_clock::time_point g_last_asked;
bool g_running = false;

std::optional<NowPlayingTrack> ReadPlayingSession() {
  try {
    auto manager =
        GlobalSystemMediaTransportControlsSessionManager::RequestAsync().get();
    for (auto const& session : manager.GetSessions()) {
      auto status = session.GetPlaybackInfo().PlaybackStatus();
      if (status != GlobalSystemMediaTransportControlsSessionPlaybackStatus::
                        Playing) {
        continue;
      }
      auto properties = session.TryGetMediaPropertiesAsync().get();
      std::wstring title(properties.Title());
      if (title.empty()) {
        continue;
      }
      return NowPlayingTrack{title, std::wstring(properties.Artist())};
    }
  } catch (...) {
  }
  return std::nullopt;
}

// Returns false once nobody has asked for a while, after clearing the cache.
bool Publish(std::optional<NowPlayingTrack> track) {
  std::lock_guard<std::mutex> lock(g_mutex);
  if (std::chrono::steady_clock::now() - g_last_asked > kIdleAfter) {
    g_track.reset();
    g_running = false;
    return false;
  }
  g_track = std::move(track);
  return true;
}

void Work() {
  winrt::init_apartment(winrt::apartment_type::multi_threaded);
  while (Publish(ReadPlayingSession())) {
    std::this_thread::sleep_for(kReadInterval);
  }
}

}  // namespace

std::optional<NowPlayingTrack> CurrentNowPlaying() {
  std::lock_guard<std::mutex> lock(g_mutex);
  g_last_asked = std::chrono::steady_clock::now();
  if (!g_running) {
    g_running = true;
    std::thread(Work).detach();
  }
  return g_track;
}
