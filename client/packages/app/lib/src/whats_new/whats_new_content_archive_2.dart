// SPDX-License-Identifier: Apache-2.0
/// A second era of older entries for `whatsNewEntries`, split out for the
/// same reason `whats_new_content_archive.dart` was: keep both the live
/// file and each archive under the review budget as the list keeps growing
/// release over release.
///
/// The boundary is size and nothing else: everything from 0.27.0 up to and
/// including 0.38.0 is here. `whats_new_content_archive.dart` holds
/// everything before that, and `whats_new_content.dart` holds what came
/// after. When this file gets close to the ceiling, start a third era file
/// rather than growing this one further.
library;

import 'whats_new_content.dart';

/// Prepended to the recent entries in `whats_new_content.dart`, right after
/// `whatsNewArchiveEntries`; nothing here is meant to be read on its own.
const List<WhatsNewEntry> whatsNewArchiveEntries2 = [
  WhatsNewEntry(
    version: '0.27.0',
    headline: 'Channels can be grouped into categories',
    points: [
      WhatsNewPoint(
        'Any channel can be dragged into a category, and categories collapse.',
      ),
      WhatsNewPoint(
        'Clicking a voice channel joins the call straight away. The lobby '
        'screen that used to sit in between is gone.',
      ),
      WhatsNewPoint(
        'Settings gained a 12 or 24 hour clock, a high contrast mode, and a '
        'reduce-motion switch that does not depend on your system setting.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.28.0',
    headline: 'A direct message shows when a call is running in it',
    points: [
      WhatsNewPoint(
        'You no longer have to open the conversation to find out somebody is '
        'waiting on a call in it.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.29.0',
    headline: 'The channel list, and the version you are actually running',
    points: [
      WhatsNewPoint(
        'The channel area has a CHANNELS header to match DIRECT MESSAGES, and '
        'creating a channel or a category moved into the Space menu.',
      ),
      WhatsNewPoint(
        'The sidebar edge is a plain line you click to collapse, rather than a '
        'wide bar you drag.',
      ),
      WhatsNewPoint(
        'Settings shows this build\'s real version. It had been reporting '
        '0.1.0 on every build since the first one.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.30.0',
    headline: 'Notification sounds, and choosing what you hear about',
    points: [
      WhatsNewPoint(
        'The notification sounds play now. They had been generated and sitting '
        'unused since July with nothing wired up to play them.',
      ),
      WhatsNewPoint(
        'Notifications can be set per account, including mentions only.',
      ),
      WhatsNewPoint(
        'Space settings gained a usage page - message totals, busiest hours - '
        'which is off by default and computes nothing while it is off.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.31.0',
    headline: 'Images on the canvas, camera bubbles, and a call recap',
    points: [
      WhatsNewPoint(
        'Paste an image onto the canvas, then drag it, resize it, or change '
        'what sits on top of what.',
      ),
      WhatsNewPoint(
        'A call puts each person\'s camera on the canvas as a bubble you can '
        'move around.',
      ),
      WhatsNewPoint(
        'Hanging up shows a short recap of who was there and how long, rather '
        'than dropping you onto a blank screen.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.32.0',
    headline: 'The canvas got notes and shapes',
    points: [
      WhatsNewPoint('There is more than a pen now: sticky notes and shapes.'),
      WhatsNewPoint(
        'You watch somebody draw a stroke while they are drawing it, instead '
        'of it appearing all at once when they let go.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.33.0',
    headline: 'One floating dock, so a call keeps its controls while you draw',
    points: [
      WhatsNewPoint(
        'The canvas tools and the call controls used to be two separate bars '
        'that fought for the same space. They are one dock now.',
      ),
      WhatsNewPoint(
        'Middle-click drags the canvas, shift-scroll pans it, and '
        'right-clicking an object gives it its own menu.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.34.0',
    headline: 'Your camera and your screen are objects on the canvas',
    points: [
      WhatsNewPoint(
        'A camera or a screen share can be moved and resized like anything '
        'else you have placed, rather than being stuck in a fixed tile.',
      ),
      WhatsNewPoint(
        'The voice screen is one main stage with a filmstrip under it, in '
        'place of the three separate boxes it used to show.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.35.0',
    headline: 'Where you put a camera on the canvas is shared, and it stays',
    points: [
      WhatsNewPoint(
        'Moving somebody\'s camera or screen moves it for everybody, and the '
        'arrangement survives the call ending.',
      ),
      WhatsNewPoint(
        'Polls, spoilers and author names can be reached with the keyboard, '
        'and every focusable control draws the same focus ring.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.36.0',
    headline: 'Buttons now match what you can do in that channel',
    points: [
      WhatsNewPoint(
        'Actions used to be offered based on your permissions across the whole '
        'Space, while the server decided per channel. So a moderator denied '
        'something in one channel was still shown actions there that could '
        'only fail, and actions a channel allowed them were hidden.',
      ),
      WhatsNewPoint(
        'The poll composer and the poll card were both redesigned.',
      ),
      WhatsNewPoint(
        'A direct message no longer offers a member list, a canvas button or a '
        'channel hash, none of which it ever had.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.37.0',
    headline: 'On desktop, closing the window keeps the app running',
    points: [
      WhatsNewPoint(
        'Closing sends it to the tray. On a desktop with no tray it minimises '
        'instead, and says so rather than pretending.',
      ),
      WhatsNewPoint(
        'Launching it again focuses the window already open, instead of '
        'starting a second copy.',
      ),
      WhatsNewPoint(
        'Voice settings has a "join calls with your camera on" preference, '
        'remembered between launches.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.38.0',
    headline: 'Reordering categories, and a canvas tile full screen',
    points: [
      WhatsNewPoint(
        'Categories can be dragged into order from the categories screen.',
      ),
      WhatsNewPoint(
        'A camera or screen tile on the canvas opens full screen, and tiles '
        'wrap to the pane rather than running off the edge of it.',
      ),
      WhatsNewPoint(
        'A channel row\'s menu was swallowing every attempt to drag that row '
        'into a new position.',
      ),
    ],
  ),
];
