#include "now_playing_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

#include "now_playing_smtc.h"
#include "utils.h"

void RegisterNowPlayingChannel(flutter::BinaryMessenger* messenger) {
  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      channel;
  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "slimm/now_playing",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
             result) {
        if (call.method_name() != "current") {
          result->NotImplemented();
          return;
        }
        auto track = CurrentNowPlaying();
        if (!track) {
          result->Success();
          return;
        }
        flutter::EncodableMap reply;
        reply[flutter::EncodableValue("title")] =
            flutter::EncodableValue(Utf8FromUtf16(track->title.c_str()));
        reply[flutter::EncodableValue("artist")] =
            flutter::EncodableValue(Utf8FromUtf16(track->artist.c_str()));
        result->Success(flutter::EncodableValue(reply));
      });
}
