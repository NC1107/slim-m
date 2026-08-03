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
