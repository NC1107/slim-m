// SPDX-License-Identifier: Apache-2.0
/// Older entries for `whatsNewEntries`, split out purely to keep both files
/// under the review budget as the list keeps growing release over release.
///
/// The boundary is size and nothing else: everything up to and including
/// 0.26.0 is here, and `whats_new_content.dart` holds what came after. That
/// puts this file just past the 300-line review budget already, so whoever
/// next moves entries down out of the recent file should start a second era
/// file here rather than growing this one further.
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
  WhatsNewEntry(
    version: '0.20.2',
    headline: 'Opening a DM with someone you have blocked now says so',
    points: [
      WhatsNewPoint(
        'It used to look empty and silently fail to send. Now it explains '
        'why and offers an Unblock button.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.20.3',
    headline: 'Attaching and pasting a photo on iPhone and Android',
    points: [
      WhatsNewPoint(
        'The attach button on a phone now offers your photo library, not '
        'just the Files browser.',
      ),
      WhatsNewPoint('Your profile picture picker got the same choice.'),
      WhatsNewPoint(
        'If you have copied an image, the attach button now offers Paste '
        'image as well.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.21.1',
    headline: 'Renaming yourself now reaches your old messages too',
    points: [
      WhatsNewPoint(
        'Changing your display name now updates it on messages you have '
        'already sent, not just new ones.',
      ),
      WhatsNewPoint(
        'The message box\'s placeholder text is now vertically centred '
        'instead of stuck at the top.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.21.3',
    headline: 'Fixes from using the app on a phone',
    points: [
      WhatsNewPoint(
        'Save and Cancel no longer run off the edge of the screen while '
        'editing a message.',
      ),
      WhatsNewPoint(
        'The message menu and a few settings sheets now use the full '
        'width on a phone instead of a cramped floating card.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.21.4',
    headline: 'Paste image is back on iOS',
    points: [
      WhatsNewPoint(
        'Pasting an image on iOS briefly stopped working after the last '
        'update. It is fixed - the Paste image button is back.',
        warn: true,
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.22.0',
    headline: 'Swipe from the left edge to open the channel list',
    points: [
      WhatsNewPoint(
        'Moderators can now act on a report directly: jump to the '
        'message, delete it, or time out or remove the author.',
      ),
      WhatsNewPoint(
        'Your profile picture now shows a camera badge, so it is obvious '
        'you can tap to change it.',
      ),
      WhatsNewPoint(
        'The jump-to-latest button is less intrusive, and reactions sit '
        'closer to their message.',
      ),
      WhatsNewPoint(
        'On a phone, swipe in from the left edge to open the channel '
        'list, the way most messaging apps work. Swipe or tap outside to '
        'close it.',
      ),
      WhatsNewPoint(
        'You can now reply to a specific message. Pick Reply from its '
        'menu; tap the quote to jump to the original.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.23.0',
    headline: 'Calling someone in a direct message',
    points: [
      WhatsNewPoint(
        'A direct message now has a Call button in its header. Mic and '
        'camera stay off until you join.',
      ),
      WhatsNewPoint(
        'Stepping away to read messages does not hang up - the call keeps '
        'running in a collapsed strip.',
      ),
      WhatsNewPoint(
        'Blocking someone stops a call the same way it already stops a '
        'message: neither of you can ring the other.',
      ),
      WhatsNewPoint(
        'Opening the canvas now fades in smoothly instead of snapping '
        'into view.',
      ),
      WhatsNewPoint(
        'Two small animations were polished: the first-connection '
        'identity screen and your sidebar status avatar.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.24.0',
    headline: 'Threads',
    points: [
      WhatsNewPoint(
        'A message\'s menu now offers Reply in thread: it opens a side '
        'conversation attached to that message, keeping tangents out of '
        'the main channel.',
      ),
      WhatsNewPoint(
        'A thread works just like a regular channel, and anyone who can '
        'read the parent channel can read and post in it too.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.24.2',
    headline: 'Pasting an image on iPhone works from the text box',
    points: [
      WhatsNewPoint(
        'Press and hold the message box and pick Paste. iOS no longer asks '
        'for permission each time.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.25.0',
    headline: 'A reply count under threaded messages',
    points: [
      WhatsNewPoint(
        'A message with a thread now shows "N replies" underneath it - '
        'tap to open.',
      ),
      WhatsNewPoint(
        'When there has been a reply, it also says when the most recent '
        'one landed.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.25.1',
    headline: 'The jump-to-latest arrow no longer shows up unprompted',
    points: [
      WhatsNewPoint(
        'It no longer appears just from switching channels - only after '
        'you have actually scrolled away from the newest message.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.25.2',
    headline: 'Threads no longer show two header bars stacked together',
    points: [
      WhatsNewPoint(
        'Opening a thread used to show two header bars stacked on top of '
        'each other, and some of those buttons acted on the wrong '
        'conversation. It is one simple bar now: back, the title, and '
        'search.',
        warn: true,
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.26.0',
    headline: 'The composer remembers what you were typing',
    points: [
      WhatsNewPoint(
        'Switching channels no longer loses what you were typing - each '
        'channel keeps its own draft.',
      ),
      WhatsNewPoint(
        'An attached file now shows up immediately instead of vanishing '
        'until the upload finishes.',
      ),
      WhatsNewPoint(
        'A picked photo gets a small thumbnail preview, not just a '
        'filename.',
      ),
      WhatsNewPoint(
        'If an upload fails, you can now retry or remove it instead of it '
        'disappearing silently.',
      ),
    ],
  ),
];
