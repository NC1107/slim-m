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
/// mitigation is naming the risk here rather than pretending automation
/// covers it: add an entry in the same PR that ships something a user would
/// notice, the way `docs/` entries already accompany a landed change in this
/// repo.
library;

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
