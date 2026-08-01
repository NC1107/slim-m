// SPDX-License-Identifier: Apache-2.0
/// Older entries for `whatsNewEntries`, split out purely to keep both files
/// under the review budget as the list keeps growing release over release.
library;

import 'whats_new_content.dart';

/// Prepended to the recent entries in `whats_new_content.dart`; nothing here
/// is meant to be read on its own.
const List<WhatsNewEntry> whatsNewArchiveEntries = [
  WhatsNewEntry(
    version: '0.17.2',
    headline: 'Message history now reconciles instead of only appending',
    points: [
      WhatsNewPoint(
        'This update rebuilds your local message cache once. Right after '
        'installing it you will see only the newest 50 messages in each '
        'channel; nothing was deleted on the server, and scrolling up '
        'reloads the rest exactly as it always has.',
        warn: true,
      ),
      WhatsNewPoint(
        'That rebuild is also what fixes messages silently drifting out of '
        'sync between devices, which is what this change was for.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.18.0',
    headline: 'A round of fixes from using the app on real devices',
    points: [
      WhatsNewPoint(
        'Avatars and images no longer reload every time you switch channel. '
        'They were only ever held while something was on screen looking at '
        'them, so leaving a channel threw them away.',
      ),
      WhatsNewPoint(
        'Message rows no longer jump when the pointer crosses them, two '
        'channels no longer overlay each other while switching, and one '
        'image can no longer fill the whole window.',
      ),
      WhatsNewPoint(
        'On a phone, a long press now raises a sheet from the bottom rather '
        'than a menu floating under your thumb.',
      ),
      WhatsNewPoint(
        'The channel list collapses, notes to self reads as a direct message '
        'with You, and you can hide it and find it again by searching your '
        'own name.',
      ),
      WhatsNewPoint(
        'Pasting an image into the composer works in the browser build. '
        'Flutter has no image clipboard on desktop or mobile, so there it '
        'still only pastes text.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.19.0',
    headline: 'Formatting, lists and spoilers in messages',
    points: [
      WhatsNewPoint(
        'Messages take **bold**, *italic*, ~~strikethrough~~ and '
        '||spoiler|| markers. A spoiler stays covered until it is tapped.',
      ),
      WhatsNewPoint(
        'Bullet and numbered lists, quotes and headings render as what they '
        'are rather than as the characters you typed. Pressing Enter inside '
        'a list carries the marker to the next line, and pressing it on an '
        'empty item ends the list.',
      ),
      WhatsNewPoint(
        'Ctrl+B and Ctrl+I wrap whatever you have selected, or drop the '
        'markers where the caret is.',
      ),
      WhatsNewPoint(
        'Text that only looks like formatting is left alone: snake_case '
        'names, a lone asterisk between spaces, and anything inside a code '
        'span or a code fence.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.20.0',
    headline: 'Jump straight to a message, and reorder your channels',
    points: [
      WhatsNewPoint(
        'Tapping a search result, a pinned message, or a message hit in the '
        'quick switcher scrolls straight to it and briefly highlights it, '
        'instead of leaving you to go find it yourself.',
      ),
      WhatsNewPoint(
        'If the message is further back than what has loaded, it pages in '
        'the history it needs first. If it genuinely cannot be found, you '
        'are told so rather than being left scrolled to nowhere.',
      ),
      WhatsNewPoint(
        'If you manage channels, press and hold a text or voice channel to '
        'drag it to a new spot. The order is shared by the whole Space, not '
        'just your device, so everyone sees channels in the same place.',
      ),
      WhatsNewPoint(
        'If a reorder cannot be saved, the sidebar says so and lets you '
        'retry rather than quietly snapping back with no explanation.',
      ),
      WhatsNewPoint(
        'On a computer you can drag across message text to select part of '
        'it, or several messages at once. On a phone a long press still '
        'opens the message actions, which is what that gesture is for '
        'there.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.20.1',
    headline: 'The day divider no longer flashes when you send',
    points: [
      WhatsNewPoint(
        'Sending a message into a channel that had not finished loading its '
        'history put a Today divider above it for a moment and then took it '
        'away again. The divider now waits until enough history is known '
        'for it to mean anything.',
      ),
    ],
  ),
];
