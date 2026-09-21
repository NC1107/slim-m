// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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
import 'whats_new_content_archive_3.dart';
import 'whats_new_content_archive_4.dart';

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
  ...whatsNewArchiveEntries3,
  ...whatsNewArchiveEntries4,
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
  WhatsNewEntry(
    version: '0.79.0',
    headline: 'Modules that make a noise, and a safer keychain',
    points: [
      WhatsNewPoint(
        'A module can ask slim-m to play a short sound, built from the same '
        'notes the notification chimes use, so it sounds like the rest of '
        'the app. It never plays on its own: only in answer to your own tap, '
        'and you can turn module sound off entirely in settings.',
      ),
      WhatsNewPoint(
        'Code blocks can run through a self-hosted runner, and the Run '
        'button only appears for a language a runner actually named.',
      ),
      WhatsNewPoint(
        'The app notices an update while it is still open instead of waiting '
        'for a restart, a YouTube link preview says which channel it came '
        'from, and macOS and Windows keep their secrets in the system '
        'keychain rather than beside the app.',
      ),
    ],
  ),
  WhatsNewEntry(
    version: '0.80.0',
    headline: 'Bots, links to a single message, and modules worth building',
    points: [
      WhatsNewPoint(
        'A Space can have bots. They are their own accounts rather than a '
        'flag on yours, they are badged as bots wherever they speak, and an '
        'administrator can revoke one without touching anybody else. There '
        'is a worked example and a guide for writing your own.',
      ),
      WhatsNewPoint(
        'Copy a link to any message and follow one back, from inside the app '
        'or from a link somebody sent you elsewhere. A link to a different '
        'Space is refused rather than followed.',
      ),
      WhatsNewPoint(
        'A half-typed message survives closing the app, and a call dropped '
        'by a flaky network comes back on its own instead of waiting for you '
        'to notice and tap.',
      ),
      WhatsNewPoint(
        'Modules can draw far more: arbitrary shapes, images, gradients, '
        'text boxes you type into, a grid placed anywhere on the scene, and '
        'a screen of their own to open on. There is a music box in the '
        'marketplace built out of all of it.',
      ),
      WhatsNewPoint(
        'An administrator can issue a password reset code from a member\'s '
        'profile, and delete an account for good. Who can join now sits with '
        'the invites, and the Dock can update every module in one press.',
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
