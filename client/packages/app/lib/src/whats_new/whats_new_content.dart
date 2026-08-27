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
import 'whats_new_content_archive_2.dart';

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
  ...whatsNewArchiveEntries2,
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
