#ifndef RUNNER_NOW_PLAYING_CHANNEL_H_
#define RUNNER_NOW_PLAYING_CHANNEL_H_

#include <flutter/binary_messenger.h>

// Answers the Dart side's `slimm/now_playing` `current` call with the SMTC
// track, or null when nothing is playing (decision 0044).
void RegisterNowPlayingChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_NOW_PLAYING_CHANNEL_H_
