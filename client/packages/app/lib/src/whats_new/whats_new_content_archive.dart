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
    headline: 'Message history now stays in sync across devices',
    points: [
      WhatsNewPoint(
        'This update resets your local message cache once. You will see '
        'only the newest 50 messages per channel at first - nothing was '
        'deleted, and scrolling up reloads the rest.',
        warn: true,
      ),
      WhatsNewPoint(
        'It also fixes messages silently drifting out of sync between your '
        'devices.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.18.0',
    headline: 'A round of fixes from using the app on real devices',
    points: [
      WhatsNewPoint(
        'Avatars and images no longer reload every time you switch '
        'channels.',
      ),
      WhatsNewPoint(
        'Fixed message rows jumping under your cursor, channels briefly '
        'overlapping when switching, and one oversized image filling the '
        'whole window.',
      ),
      WhatsNewPoint(
        'On a phone, long-pressing a message opens a bottom sheet instead '
        'of a floating menu under your thumb.',
      ),
      WhatsNewPoint(
        'The channel list can now collapse, and Notes to Self reads as a '
        'direct message with "You" - hide it or find it again by searching '
        'your own name.',
      ),
      WhatsNewPoint(
        'Pasting an image now works in the browser version. Desktop and '
        'mobile still only paste text.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.19.0',
    headline: 'Formatting, lists and spoilers in messages',
    points: [
      WhatsNewPoint(
        'Messages take **bold**, *italic*, ~~strikethrough~~ and '
        '||spoiler|| markers. A spoiler stays covered until tapped.',
      ),
      WhatsNewPoint(
        'Bullet and numbered lists, quotes and headings now render '
        'properly instead of showing the raw characters you typed.',
      ),
      WhatsNewPoint('Ctrl+B and Ctrl+I wrap whatever text you have selected.'),
      WhatsNewPoint(
        'Text that only looks like formatting, like snake_case names, is '
        'left alone.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.20.0',
    headline: 'Jump straight to a message, and reorder your channels',
    points: [
      WhatsNewPoint(
        'Tapping a search result, a pinned message, or a quick-switcher '
        'hit now jumps straight to it and briefly highlights it.',
      ),
      WhatsNewPoint(
        'If the message has not loaded yet, it fetches the history it '
        'needs first. If it truly cannot be found, you are told so.',
      ),
      WhatsNewPoint(
        'If you manage channels, press and hold one to drag it to a new '
        'spot. The new order shows for everyone in the Space.',
      ),
      WhatsNewPoint('If a reorder fails to save, you are told and can retry.'),
      WhatsNewPoint(
        'On a computer, you can now drag to select message text. On a '
        'phone, a long press still opens message actions.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.20.1',
    headline: 'The day divider no longer flashes when you send',
    points: [
      WhatsNewPoint(
        'Fixed a "Today" divider briefly flashing above a message you had '
        'just sent, in a channel still loading its history.',
      ),
    ],
  ),
];
