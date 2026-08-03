// SPDX-License-Identifier: Apache-2.0
#ifndef FLUTTER_CLIPBOARD_IMAGE_CHANNEL_H_
#define FLUTTER_CLIPBOARD_IMAGE_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

// The desktop half of the composer's paste bridge; the Dart side is
// `composer_clipboard_image_stub.dart`, which owns the channel and method
// names shared with the iOS and Android implementations
// (ClipboardImagePlugin.swift, ClipboardImageChannel.kt). Only "hasImage" and
// "readImage" are implemented; anything else falls through to
// fl_method_call_respond_not_implemented, the same MissingPluginException the
// stub already tolerates for the mobile-only methods.
void clipboard_image_channel_register(FlBinaryMessenger* messenger);

#endif  // FLUTTER_CLIPBOARD_IMAGE_CHANNEL_H_
