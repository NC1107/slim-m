// SPDX-License-Identifier: Apache-2.0
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Installs the swizzle documented in ClipboardPasteBridge.m so the iOS
/// system edit menu's own Paste item also appears - and works - when the
/// pasteboard holds an image rather than a string.
///
/// `onImage` is invoked synchronously, from inside iOS's own dispatch of the
/// native `paste:` action, with the pasteboard's image already read as PNG
/// data; see the .m file for why that ordering is load-bearing.
///
/// Returns whether the swizzle actually installed. A caller must treat NO as
/// "unavailable, fall back to the older poll-and-tap route" rather than as an
/// error: it means Flutter's private text input class or one of the two
/// selectors this depends on was not found at runtime, which fails safe by
/// design (see the .m file's doc comment) rather than crashing.
BOOL SlimmInstallClipboardPasteBridge(void (^onImage)(NSData *pngData));

NS_ASSUME_NONNULL_END
