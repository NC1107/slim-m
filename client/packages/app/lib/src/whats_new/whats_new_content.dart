// SPDX-License-Identifier: Apache-2.0
/// The hand-written text the what's-new sheet shows, one entry per released
/// version that has something worth telling a returning user.
///
/// Hand-written rather than parsed from `client/CHANGELOG.md`, and that is a
/// choice with a real failure mode, written down rather than hidden: nothing
/// forces a contributor to add an entry here when they cut a release, so a
/// version can ship with genuinely user-facing changes and nothing shows up.
/// The alternative was rejected on the merits, not by default. The changelog
/// is release-please's own output (conventional-commit subjects, one per
/// squashed PR) and is explicitly a generated file this project never hand
/// edits; a `fix: a restore frame with no ids must ask the feed, not be
/// applied as empty` line is accurate and useless to a person who just wants
/// to know what changed for them. Parsing it would give a sheet that always
/// appears and never says anything worth reading, which is worse than one
/// that sometimes says nothing at all because nobody wrote it yet. The
/// mitigation was naming the risk here rather than pretending automation
/// covers it: add an entry in the same PR that ships something a user would
/// notice, the way `docs/` entries already accompany a landed change in this
/// repo.
///
/// That mitigation was not enough, and the failure mode it named happened
/// exactly as written. The newest entry sat at 0.26.0 while twelve releases
/// shipped, so the sheet correctly showed nothing every time and no one could
/// tell that apart from there being nothing to say. Naming a risk is not a
/// gate, so there is one now: `whats_new_freshness_test.dart` fails when the
/// newest entry here falls too far behind the version the app reports. It
/// still cannot know whether an entry is any *good*, only that somebody
/// looked, which is the most a mechanical check can honestly claim here.
library;

import 'whats_new_content_archive.dart';

/// One line of an entry. [warn] renders it in the same tone a data-affecting
/// or otherwise surprising change gets elsewhere in this app (`AppCallout`'s
/// warn tone), rather than as an ordinary bullet a user could skim past.
class WhatsNewPoint {
  const WhatsNewPoint(this.body, {this.warn = false});

  final String body;
  final bool warn;
}

/// Everything shown for one released version.
class WhatsNewEntry {
  const WhatsNewEntry({
    required this.version,
    required this.headline,
    required this.points,
  });

  /// The client version this shipped in, matching `client/pubspec.yaml` at
  /// release time. Compared with [compareVersions], not string equality, so
  /// a later patch of the same line does not need its own entry to still
  /// pick this one up on the way past.
  final String version;
  final String headline;
  final List<WhatsNewPoint> points;
}

/// Every entry shipped so far, oldest first. [pendingWhatsNewEntries] keeps
/// that order; the sheet itself decides how to present it.
const List<WhatsNewEntry> whatsNewEntries = [
  ...whatsNewArchiveEntries,
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
];

/// Parses a dot-separated version like `0.17.2` into its numeric segments,
/// treating anything after a `-` or `+` (a pre-release or build tag) as not
/// part of the ordering. A segment that will not parse reads as 0 rather
/// than throwing, since a malformed version must degrade to "equal", never
/// crash the check that decides whether to show anything at all.
List<int> _versionSegments(String version) {
  final core = version.split(RegExp(r'[-+]')).first;
  return core.split('.').map((part) => int.tryParse(part) ?? 0).toList();
}

/// Ordinary three-way version compare: negative if [a] precedes [b], zero if
/// equal, positive if [a] follows. Segment count differing (`0.17` against
/// `0.17.2`) treats a missing trailing segment as 0.
int compareVersions(String a, String b) {
  final left = _versionSegments(a);
  final right = _versionSegments(b);
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final l = i < left.length ? left[i] : 0;
    final r = i < right.length ? right[i] : 0;
    if (l != r) return l.compareTo(r);
  }
  return 0;
}

/// The entries a person on [currentVersion] has not yet been shown, having
/// last seen [lastSeen] (null meaning no what's-new version has ever been
/// recorded for this install).
///
/// Every entry from after [lastSeen] up to and including [currentVersion] is
/// returned, not only the entry matching [currentVersion] exactly: someone
/// who skipped launching the app across several releases should catch up on
/// all of them at once rather than only ever seeing the latest.
///
/// [entries] defaults to [whatsNewEntries]; a test overrides it with a small
/// fixture so the filter is checked without depending on which real releases
/// happen to have an entry today.
List<WhatsNewEntry> pendingWhatsNewEntries({
  required String? lastSeen,
  required String currentVersion,
  List<WhatsNewEntry> entries = whatsNewEntries,
}) {
  return entries
      .where((entry) => compareVersions(entry.version, currentVersion) <= 0)
      .where(
        (entry) =>
            lastSeen == null || compareVersions(entry.version, lastSeen) > 0,
      )
      .toList(growable: false);
}
