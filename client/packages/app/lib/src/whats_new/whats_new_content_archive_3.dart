// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Older entries for `whatsNewEntries`, split out purely to keep every
/// file under the review budget as the list keeps growing release over
/// release - the third such split, after `whats_new_content_archive.dart`
/// (up to 0.26.0) and `whats_new_content_archive_2.dart` (through 0.38.0).
///
/// The boundary is size and nothing else: 0.41.0 through 0.54.0 are here,
/// and `whats_new_content.dart` holds what came after. Nothing here is
/// edited again - a shipped release's text is a record of what shipped.
library;

import 'whats_new_content.dart';

/// Spliced into `whatsNewEntries` after [whatsNewArchiveEntries2].
const List<WhatsNewEntry> whatsNewArchiveEntries3 = [
  WhatsNewEntry(
    version: '0.41.0',
    headline: 'The app moves now',
    points: [
      WhatsNewPoint(
        'Menus, pickers, hover states and status dots animate in and out '
        'instead of teleporting - and every one of them still collapses '
        'to an instant swap under reduce motion.',
      ),
      WhatsNewPoint(
        'People joining or leaving a call arrive and depart in place, the '
        'typing indicator has real dots, reactions pop, and a sent message '
        'hands off to its timestamp instead of snapping.',
      ),
      WhatsNewPoint(
        'Remote canvas cursors glide instead of stepping, settings flash a '
        'small Saved when a change lands, and the first screens you ever '
        'see finally arrive with some motion of their own.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.42.0',
    headline: 'Nineteen things at once',
    points: [
      WhatsNewPoint(
        'Messages grew up: forward one to any channel or DM, swipe to '
        'reply one-handed, mention @everyone or @here (permission-gated), '
        'and set a status line under your name.',
      ),
      WhatsNewPoint(
        'Search takes from:, in:, has: and before:/after: filters, GIF '
        'search lands in the composer when your server configures a '
        'provider, and threads finally have a list, unread state, and a cap.',
      ),
      WhatsNewPoint(
        'Calls: push-to-talk and a mic sensitivity slider, screen shares '
        'can carry this device audio where the platform allows, and the '
        'canvas is one tap from the call dock.',
      ),
      WhatsNewPoint(
        'Mute any channel (or narrow it to mentions), failed sends retry '
        'themselves when the connection returns, notification sounds carry '
        'a matching buzz, and rows grow with large text.',
      ),
      WhatsNewPoint(
        'For operators: a Prometheus metrics route, per-member storage '
        'numbers, opt-in message retention, and macOS plus Windows builds '
        'now compile in CI.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.45.0',
    headline: 'Cleaner, crisper, lighter',
    points: [
      WhatsNewPoint(
        'Select several messages and delete them in one go, and the '
        'settings screens got a real going-over - each section reads as '
        'its own thing now instead of one flat scroll.',
      ),
      WhatsNewPoint(
        'Avatars and profile pictures render sharp on scaled desktop '
        'displays instead of soft, and the desktop title bar dropped a '
        'stray underline it should never have shown.',
      ),
      WhatsNewPoint(
        'The member list lost its search box and sort toggle, since '
        'typing @name already finds anyone, and Appearance settings gained '
        'an image-cache size control if you want to trade a little memory '
        'for a lot less.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.48.0',
    headline: 'Threads, replies, and a smoother start',
    points: [
      WhatsNewPoint(
        'Opening a thread from a link, a notification, or a reload now docks '
        'it beside the channel on a wide window - the same place tapping into '
        'one in the app puts it - instead of covering the conversation with a '
        'sheet.',
      ),
      WhatsNewPoint(
        'The reply bar above the composer is rounder and more compact, and '
        'when you reply to a message that was only a photo or a file it names '
        'that now, rather than showing a blank line.',
      ),
      WhatsNewPoint(
        'On a phone a fresh launch shows a brief boot screen while it '
        'connects, so you no longer land on an empty home for a moment. The '
        'join screen also leads with a plain line about what this is, on a '
        'tidier, narrower panel.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.50.0',
    headline: 'Performance settings, and room for bigger files',
    points: [
      WhatsNewPoint(
        'Settings has a Performance section now. Choose whether images and '
        'GIFs load on their own or wait for a tap, how sharply inline '
        'previews decode, how much memory the image cache keeps, and how '
        'many older messages a scroll back through history loads at a time.',
      ),
      WhatsNewPoint(
        'Attachments can be much larger - up to 1 GB by default - and the '
        'server streams an upload to disk as it arrives rather than holding '
        'the whole file in memory.',
      ),
      WhatsNewPoint(
        'A space admin can set the per-channel canvas object limit for '
        'everyone, trading how much a board can hold against how heavy a busy '
        'canvas is to load and draw.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.51.0',
    headline: 'A status, bulk emoji, and one menu everywhere',
    points: [
      WhatsNewPoint(
        'Tap your own avatar in the sidebar to set a custom status - a short '
        'line under your name, cleared as easily as it is set.',
      ),
      WhatsNewPoint(
        'Admins can add custom emoji in bulk from a zip file: each image '
        'becomes an emoji named after its file, so party_blob.gif arrives as '
        ':party_blob:.',
      ),
      WhatsNewPoint(
        'A channel\'s menu is the same however you open it. The three-dot '
        'button, a right-click and a long-press now all show one menu, with '
        'the same actions in the same order.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.54.0',
    headline: 'Statuses under names, a calmer launch, faster joining',
    points: [
      WhatsNewPoint(
        'A custom status now sits neatly under its owner\'s name in the '
        'member list, with the picture centred across both lines instead of '
        'the status floating below the row.',
      ),
      WhatsNewPoint(
        'Opening the app no longer flashes a white screen before the dark '
        'interface arrives - the very first frame matches the app\'s own '
        'surface.',
      ),
      WhatsNewPoint(
        'Joining the official Space skips a step: the sign-in screen opens '
        'straight on creating an account, since arriving there means you do '
        'not have one yet.',
      ),
      WhatsNewPoint(
        'On desktop the tray icon earned its keep - presence, call controls '
        'and settings live in its menu - and replies to a photo now show a '
        'small thumbnail instead of a bare label.',
      ),
    ],
  ),
];
