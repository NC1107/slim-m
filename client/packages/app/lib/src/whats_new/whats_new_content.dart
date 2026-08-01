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
    version: '0.20.2',
    headline: 'Opening a DM with someone you have blocked now says so',
    points: [
      WhatsNewPoint(
        'It used to just look empty, with a composer that would fail if you '
        'tried to use it. Now it explains what is going on and gives you an '
        'Unblock button right there.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.20.3',
    headline: 'Attaching and pasting a photo on iPhone and Android',
    points: [
      WhatsNewPoint(
        'The attach button on a phone used to only open the Files browser, '
        'which cannot see your camera roll at all. It now asks whether you '
        'want your photo library or files, the same choice you get '
        'attaching a photo anywhere else.',
      ),
      WhatsNewPoint(
        'Your profile picture picker got the same choice, so a photo that '
        'arrived by download or AirDrop is no longer stuck.',
      ),
      WhatsNewPoint(
        'If you have copied an image, the same attach button now offers a '
        'Paste image action. iOS may ask once whether this app can read '
        'your clipboard; that is expected and only asks the first time.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.21.1',
    headline: 'Renaming yourself now reaches your old messages too',
    points: [
      WhatsNewPoint(
        'Changing your display name used to leave every message you had '
        'already sent showing the old one on everyone else\'s screen, '
        'sometimes for good. It now updates live while everyone is '
        'connected, and catches up the moment a device reconnects.',
      ),
      WhatsNewPoint(
        'The composer\'s placeholder text now sits level with the icons '
        'beside it at rest, instead of pinned to the top of a box taller '
        'than the line of text in it.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.21.3',
    headline: 'Fixes from using the app on a phone',
    points: [
      WhatsNewPoint(
        'Save and Cancel used to overflow off the edge of a phone screen '
        'while editing, leaving no way to finish or back out of an edit. '
        'Both are reachable now, and a hardware keyboard\'s Enter and '
        'Escape shortcuts still work exactly as before.',
      ),
      WhatsNewPoint(
        'The message context menu, who can join, and the role granted on '
        'an invite all opened as a narrow floating card nested inside the '
        'sheet on a phone. They now span the full width, as one sheet.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.21.4',
    headline: 'Paste image is back on iOS',
    points: [
      WhatsNewPoint(
        'The last update hid the composer\'s Paste image action on iOS in '
        'favor of the system edit menu\'s own Paste item, which turned out '
        'not to work for images at all - so there was briefly no way to '
        'paste an image on iOS. The composer\'s own action is back and no '
        'longer hides itself.',
        warn: true,
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.22.0',
    headline: 'Swipe from the left edge to open the channel list',
    points: [
      WhatsNewPoint(
        'Reports can be acted on. Jump straight to the message, and delete '
        'it, time the author out or remove them, without leaving the queue. '
        'The card also says plainly who was reported and who reported them.',
      ),
      WhatsNewPoint(
        'Your profile picture is centred with a camera badge, so it is '
        'obvious you can tap it to change.',
      ),
      WhatsNewPoint(
        'The jump-to-latest button is out of the way, reactions sit closer '
        'to their message, and opening a direct message from the member '
        'list closes the list behind you.',
      ),
      WhatsNewPoint(
        'On a phone, swiping in from the left edge of a conversation now '
        'pulls the channel list over it, the gesture every other messaging '
        'app already trains you to reach for. Swipe it shut again or tap '
        'outside it, and picking a different channel closes it for you.',
      ),
      WhatsNewPoint(
        'The back button at the top still works exactly as it did; this is '
        'a second way to the same place, not a replacement for it.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.23.0',
    headline: 'Calling someone in a direct message',
    points: [
      WhatsNewPoint(
        'A direct message now has a Call button in its header, right next '
        'to search and pinned messages. It opens the same join preview a '
        'voice channel does, mic and camera off until you actually join.',
      ),
      WhatsNewPoint(
        'Stepping away to read messages does not hang up. The call keeps '
        'running, with the same collapsed strip and "back to the call" '
        'a voice channel already gives you.',
      ),
      WhatsNewPoint(
        'Blocking someone stops a call the same way it already stops a '
        'message: neither of you can ring the other.',
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
