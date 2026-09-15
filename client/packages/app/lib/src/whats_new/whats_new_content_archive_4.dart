// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// What's-new entries for 0.57.0 through 0.62.0, moved out of
/// `whats_new_content.dart` when writing 0.75.0 through 0.77.0 pushed that
/// file past its line budget. Same reason the three archives before this
/// exist: the list only ever grows, and the newest entries are the ones
/// anybody edits.
library;

import 'whats_new_content.dart';

const List<WhatsNewEntry> whatsNewArchiveEntries4 = [
  WhatsNewEntry(
    version: '0.57.0',
    headline: 'One place for channel settings, and calls that let you leave',
    points: [
      WhatsNewPoint(
        'A channel is configured in one screen now. Its name, description, '
        'permissions and the delete button live together, rather than a '
        'sheet holding some of it and a separate page holding the rest.',
      ),
      WhatsNewPoint(
        'Leaving a call while the canvas is open actually leaves it. Closing '
        'the canvas afterwards no longer drops you back into the call with '
        'the timer started over.',
      ),
      WhatsNewPoint(
        'On desktop a status is a text box in the menu itself, and a status '
        'you have set can be cleared in one click.',
      ),
      WhatsNewPoint(
        'Starting a screen share no longer shows a moment of leftover '
        'picture before the real one arrives.',
      ),
      WhatsNewPoint(
        'The switch-camera button only appears when you have more than one '
        'camera to switch to.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.58.0',
    headline:
        'Sharper avatars, a working Linux tray menu, and dragging files in',
    points: [
      WhatsNewPoint(
        'Drop a file straight onto the composer, or an emoji pack\'s zip '
        'file onto the emoji import card, instead of opening a picker - and '
        'a pack now imports in a few bulk batches rather than one request '
        'per image, so a big one no longer stalls partway through from '
        'being rate limited.',
      ),
      WhatsNewPoint(
        'Space settings gained a Performance section, split out of '
        'Analytics: message retention, the canvas object cap, and screen '
        'share quality each say what changing them actually costs.',
      ),
      WhatsNewPoint(
        'On desktop, a status can be cleared with the x next to its field. '
        'Your own row in the member list also updates the moment you '
        'change it, rather than sitting stale until something else '
        'refreshed it.',
      ),
      WhatsNewPoint(
        'On Linux, right-clicking the tray icon opens a menu again - it '
        'had quietly been building none at all.',
      ),
      WhatsNewPoint(
        'On desktop, the window now starts small, showing the logo and '
        'wordmark, rather than opening at full size around a lone icon. It '
        'settles into your normal window size once it has finished '
        'loading, and says what it is doing along the way: restoring your '
        'session, loading preferences, connecting, instead of sitting '
        'silent.',
      ),
      WhatsNewPoint(
        'Profile pictures are sharper too: two-letter initials no longer '
        'look bolded when they shouldn\'t, and photos no longer render '
        'soft.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.59.0',
    headline: 'A moderation history, and a startup screen you can turn off',
    points: [
      WhatsNewPoint(
        'The moderation queue has a History tab next to open reports now, '
        'showing who removed, timed out or restored someone, and when. The '
        'server has been keeping this all along - there was just nowhere to '
        'look at it.',
      ),
      WhatsNewPoint(
        'On desktop, Settings > Performance can turn the startup splash off '
        'entirely, or set how long it lingers: brief, standard, or long.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.60.0',
    headline: 'Video plays inline, and every attachment can be saved',
    points: [
      WhatsNewPoint(
        'Video attachments play right in the app now instead of sitting '
        'there as a dead chip, on Linux, Windows, macOS, Android, iOS and '
        'web. On native platforms it streams as it plays rather than '
        'downloading the whole file first.',
      ),
      WhatsNewPoint(
        'Any attachment can be saved or opened now, whatever it is - PDFs, '
        'audio, archives, all of it. Before, only four image formats '
        'rendered and everything else was a dead end with no way to get it '
        'back out of the app.',
      ),
      WhatsNewPoint(
        'Custom emoji stopped showing up as broken images. They\'re cached '
        'on disk now, so reopening the picker does not refetch everything, '
        'and a picker full of emoji no longer overwhelms the connection and '
        'fails partway through.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.60.1',
    headline: 'The channel rail opens on a narrow desktop window again',
    points: [
      WhatsNewPoint(
        'Narrowing a desktop window past the point it switches to the '
        'compact layout used to shut you out of the channel rail entirely - '
        'the edge-swipe that opens it was disabled there regardless of '
        'width, and no button stood in for it. The swipe works now.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.62.0',
    headline:
        'A tray menu that works, forwarded attachments, and a nicer video '
        'player',
    points: [
      WhatsNewPoint(
        'Clicking anything in the desktop tray menu actually does something '
        'now. Every item in it had quietly been doing nothing at all.',
      ),
      WhatsNewPoint(
        'The app starts about five seconds faster on desktop - the startup '
        'screen was waiting on a frame that could never arrive while the '
        'window stayed hidden.',
      ),
      WhatsNewPoint(
        'Forwarding a message now brings its attachments along instead of '
        'dropping them, and the picker you forward into was rebuilt with '
        'search.',
      ),
      WhatsNewPoint(
        'The inline video player got real controls: swipe down to leave '
        'fullscreen, double-tap to enter it, and the whole thing now '
        'matches the app\'s own colours instead of the system default.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.63.0',
    headline:
        'Chat inside a voice call, a private note, and a canvas '
        'right-click menu',
    points: [
      WhatsNewPoint(
        'You can read and send messages in a voice channel now without '
        'leaving the call - a side pane next to it on a wide window, or a '
        'full-screen swap with a toggle at narrower widths. Unread dots on '
        'voice channels behave the same as text channels now too.',
      ),
      WhatsNewPoint(
        'Right-click empty canvas space for a quick menu: paste an image '
        'or add a note right where you clicked, or recenter the view.',
      ),
      WhatsNewPoint(
        'You can leave a private note on someone else\'s profile now, '
        'visible only to you.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.64.0',
    headline: 'A proper emoji and GIF picker, quiet hours, and a canvas in DMs',
    points: [
      WhatsNewPoint(
        'The composer\'s emoji button now opens a real picker on a desktop '
        'window: search, categories down the side, your most-used at the '
        'top, and a GIFs tab beside them. It opens on trending rather than a '
        'blank grid. On a phone the keyboard\'s own emoji stay the better '
        'tool, so that is unchanged.',
      ),
      WhatsNewPoint(
        'Quiet hours: set a window and ordinary messages stop waking your '
        'phone inside it. Mentions and direct messages still come through, '
        'the same as when you set notifications to mentions only.',
      ),
      WhatsNewPoint(
        'A DM can have a canvas now, for working something through with one '
        'other person without needing a voice channel for it.',
      ),
      WhatsNewPoint(
        'You can close a DM out of your sidebar. It is only hidden for you, '
        'the messages stay, and it comes back on its own if they write '
        'again.',
      ),
      WhatsNewPoint(
        'Profile pictures are sharp again. They had been drawn with the '
        'wrong filter since 0.58 and looked soft throughout the app.',
      ),
      WhatsNewPoint(
        'After you report something, it now appears in your own safety '
        'settings with whether it has been dealt with - you no longer file '
        'it into silence.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.66.0',
    headline: 'Calls actually ring, and you can mention a role',
    points: [
      WhatsNewPoint(
        'Calling someone in a DM rings them. It arrives in front of whatever '
        'they are doing, with a tone that keeps going until they answer or '
        'decline, and on a desktop it brings the window forward. Before '
        'this, calling somebody did nothing at all on their end.',
      ),
      WhatsNewPoint(
        'An unanswered call gives up after 30 seconds and releases the room, '
        'rather than leaving the caller sitting in it alone.',
      ),
      WhatsNewPoint(
        'Type @[Role Name] to mention everyone holding a role. A role has to '
        'be marked mentionable in its settings first, so a large role cannot '
        'be used to wake the whole space by accident.',
      ),
      WhatsNewPoint(
        'Turning your camera off puts your picture back on the tile, instead '
        'of leaving your last frame frozen there for everyone else.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.67.0',
    headline: 'Moderate a crowd at once, and gestures that do what you meant',
    points: [
      WhatsNewPoint(
        'Select several members in the member list and remove or time out all '
        'of them in one go. A wave of throwaway accounts used to be one '
        'confirmation each, while they were still arriving.',
      ),
      WhatsNewPoint(
        'Swiping in from the left edge to open the sidebar now works from the '
        'whole edge rather than a few pixels of it, so it stops replying to '
        'the message you swiped over. Carry the same swipe further and it '
        'opens the full channel list.',
      ),
      WhatsNewPoint(
        'Right-click or long-press a category to rename or delete it '
        'directly, instead of opening a panel to find those buttons.',
      ),
      WhatsNewPoint(
        'Scrolling back through a conversation puts the keyboard away and '
        'gives you the screen to read with. A message arriving no longer '
        'closes it under you mid-sentence.',
      ),
      WhatsNewPoint(
        'A message you were sending when the app closed no longer sits as '
        'sending forever. It comes back as failed, retries itself on the next '
        'connection, and keeps what you typed either way.',
      ),
    ],
  ),
];
