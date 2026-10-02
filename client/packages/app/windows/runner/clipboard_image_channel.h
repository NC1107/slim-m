#ifndef RUNNER_CLIPBOARD_IMAGE_CHANNEL_H_
#define RUNNER_CLIPBOARD_IMAGE_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <windows.h>

// Answers the Dart side's `top.npcserver.slimm/clipboard_image` `writeImage`
// call by putting the PNG on the clipboard. `owner` must be a real window:
// a clipboard opened with no owner refuses SetClipboardData after Empty.
void RegisterClipboardImageChannel(flutter::BinaryMessenger* messenger,
                                   HWND owner);

#endif  // RUNNER_CLIPBOARD_IMAGE_CHANNEL_H_
