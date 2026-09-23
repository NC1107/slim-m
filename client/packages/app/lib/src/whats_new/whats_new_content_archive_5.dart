// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// What's-new entries for 0.70.0 through 0.78.0, moved out of
/// `whats_new_content.dart` when writing 0.81.0 through 0.83.0 pushed that
/// file past its line budget. Same reason the four archives before this
/// exist: the list only ever grows, and the newest entries are the ones
/// anybody edits.
library;

import 'whats_new_content.dart';

const List<WhatsNewEntry> whatsNewArchiveEntries5 = [
  WhatsNewEntry(
    version: '0.70.0',
    headline: 'Install modules, run code, and search across the whole space',
    points: [
      WhatsNewPoint(
        'A space can now install modules from the Dock in space settings. '
        'The first one turns a code block into something you can run, with '
        'its output shown inline like a notebook cell. Modules run sandboxed '
        'and are off until an admin installs one and grants the permission, '
        'so a space gains only what its admin chooses.',
      ),
      WhatsNewPoint(
        'Search now looks across every channel you can see, not only the one '
        'open in front of you.',
      ),
      WhatsNewPoint(
        'A channel where you were mentioned reads differently from one with '
        'only ordinary unread messages, so a question meant for you is not '
        'lost in the rest.',
      ),
      WhatsNewPoint(
        'A channel can be given a slow mode - a minimum gap between messages '
        '- as a lighter step than timing anyone out. Roles that manage the '
        'channel are exempt, and the composer shows the wait rather than '
        'refusing a message after you have typed it.',
      ),
      WhatsNewPoint(
        'A YouTube link shows its thumbnail with a play button, and nothing '
        'from YouTube loads until you choose to play it.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.73.0',
    headline: 'Launch a module as an app, and a Dock that keeps up',
    points: [
      WhatsNewPoint(
        'A module can now be an app rather than only a code block. Launch one '
        'from the composer and it opens as a surface everyone in the channel '
        'shares, so a board you step through moves for all of you at once.',
      ),
      WhatsNewPoint(
        'Draw on one of those boards by dragging across it, instead of '
        'tapping each cell.',
      ),
      WhatsNewPoint(
        'Installing a module now asks which roles may use it, right then. It '
        'grants nothing to anybody on its own, so a module installed and left '
        'alone used to appear nowhere at all, including for the admin who '
        'installed it.',
      ),
      WhatsNewPoint(
        'The Dock says when a module you have installed has a newer version, '
        'and updates it in place. Updating keeps who can use it and whether '
        'it is switched on; the only way forward before was to uninstall and '
        'start again, which lost both. You can also search the Dock, and open '
        'a module by tapping anywhere on its row.',
      ),
      WhatsNewPoint(
        'A new profile picture reaches your other devices straight away. It '
        'used to sit there looking unchanged until you quit and reopened the '
        'app, and pictures come out sharper than they did.',
      ),
      WhatsNewPoint(
        'Signing in says which server you are connecting to, on every screen '
        'that asks. When a server is one this app has not seen before, the '
        'code you are asked to confirm can now be checked: whoever runs it '
        'sees the same code in their own server log.',
      ),
      WhatsNewPoint(
        'Your status is set from the footer of the channel list and nowhere '
        'else now, rather than living in two places that could disagree. The '
        'device list names each device and says when it was last used.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.74.0',
    headline: 'Swipe-to-reply is gone, and a playing board keeps playing',
    points: [
      WhatsNewPoint(
        'Swiping a message sideways no longer starts a reply. It ran the '
        'opposite way round from other apps, and it took every sideways drag '
        'on a message - including one meant to draw on a module board. Reply '
        'is still on the message menu, where it always was.',
      ),
      WhatsNewPoint(
        'A board left playing no longer stops with "too many requests". It '
        'notices it is asking faster than the server will answer and slows '
        'down instead, and its buttons stop flickering once a generation '
        'while it runs.',
      ),
      WhatsNewPoint(
        'Drawing on a board by dragging across it now takes one round trip '
        'for the whole line rather than one per square, on modules that say '
        'they can read it that way. Game of Life 0.3.0 can.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.75.0',
    headline: 'A less bare way in',
    points: [
      WhatsNewPoint(
        'The panel beside signing in draws the mark at full size now, and '
        'the build version sits in its corner, so a bug report can quote it '
        'without digging through settings.',
      ),
      WhatsNewPoint(
        'Signing in uses the same inputs and buttons as the rest of the app '
        'rather than the framework defaults it had been using, and the '
        'submit button shows a spinner in place of its label instead of '
        'greying out.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.76.0',
    headline: 'Updates you can leave running, and a microphone you can pick',
    points: [
      WhatsNewPoint(
        'slim-m can keep itself up to date. It asks once, and if you say yes '
        'it looks for a new version each time it opens and installs it '
        'before the app starts. On Fedora that goes through dnf, so your '
        'system asks for your password when there is one to install. The '
        'switch is in Settings, under About.',
      ),
      WhatsNewPoint(
        'Voice settings can choose which microphone and speaker a call uses, '
        'and remembers the choice. A device that is unplugged falls back to '
        'the system default and says so.',
      ),
      WhatsNewPoint(
        'Drawing on the canvas works over a camera or screen-share tile '
        'instead of stopping at its edge, a shape shows its size while you '
        'drag it out rather than only once you let go, and a locked tile '
        'sent to the back no longer swallows clicks meant for things above '
        'it.',
      ),
      WhatsNewPoint(
        'Hanging up from inside the canvas closes the canvas too, rather '
        'than leaving you on an empty grid that put you back in the call '
        'when you closed it.',
      ),
      WhatsNewPoint(
        'Profile pictures uploaded from the web client were being saved '
        'softer than they needed to be. That is fixed, though a picture '
        'uploaded that way before this needs uploading again to get the '
        'sharper copy.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.77.0',
    headline: 'Locked channels, a lock of your own, and a shorter reach',
    points: [
      WhatsNewPoint(
        'A channel not everyone can see now says so, with a lock in place of '
        'the hash in the rail and in its header.',
      ),
      WhatsNewPoint(
        'On a phone, a tablet, macOS or Windows, slim-m can ask for Face ID '
        'or a fingerprint before it opens. It unlocks the app rather than '
        'signing you in, so a real sign-out still wants your password, and '
        'the task switcher no longer shows your last conversation. Not on '
        'Linux, which has nothing to ask with.',
      ),
      WhatsNewPoint(
        'Press the up arrow in an empty message box to edit the last thing '
        'you said, and select text in the box on a touch screen to bold or '
        'italicise it without a keyboard.',
      ),
      WhatsNewPoint(
        'Settings can sign out every other device at once, and says which '
        'ones are left if any refuse.',
      ),
      WhatsNewPoint(
        'Channels sit under their category rather than floating between '
        'headings, a category keeps the capitals you typed, Enter saves a '
        'channel name, and a poll no longer draws two different colours for '
        'two equal shares.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.78.0',
    headline: 'Seeing where the server spends its time',
    points: [
      WhatsNewPoint(
        'Space settings has a metrics screen: how long each route takes, how '
        'busy the database pool is, and how much memory the server is '
        'holding. Useful when something feels slow and you want a number '
        'rather than a hunch.',
      ),
    ],
  ),
];
