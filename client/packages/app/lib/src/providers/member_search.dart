// SPDX-License-Identifier: Apache-2.0
/// Finding somebody in the roster, and finding everybody who arrived at once.
///
/// The member pane groups by presence and sorts each group by name, which is
/// the right default and is useless for the one job moderation actually needs
/// the roster for: a wave of accounts joined in the last two minutes and they
/// have to be picked out of a list sorted by a property that says nothing
/// about when they arrived.
///
/// Two answers, kept here as plain functions over a list rather than inside
/// the widget, because what is worth testing is which members come back in
/// which order, and a test that has to pump a widget tree to ask that is a
/// test nobody writes twice. `member_presence.dart`'s own
/// `groupMembersByPresence` is the shape this follows.
///
/// Neither needs the server. The roster is already fetched whole, and a
/// profile already carries `createdAt` - which in this product is the join
/// time, because one deployment is one community and joining it is
/// registering into it.
library;

import 'package:slimm_api/api.dart' as api;

/// How the pane is ordering the roster.
enum MemberSort {
  /// Grouped by presence, each group by name. The pane's own long-standing
  /// default, and the right one for "who is around".
  presence,

  /// Newest account first, presence ignored. The answer to "who just arrived",
  /// which is the question a raid makes urgent.
  joined,
}

/// [members] whose username or display name contains [query], case-insensitively.
///
/// Both fields, because the two diverge on purpose: a display name is chosen
/// and changeable, a username is the handle somebody was reported under. A
/// moderator working from a report has the username; somebody scanning the
/// pane has the name they see.
///
/// An empty or whitespace-only query returns the list unchanged rather than
/// nothing, so a cleared search box is the same as no search box.
List<api.UserProfile> membersMatching(
  List<api.UserProfile> members,
  String query,
) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return members;
  return members
      .where(
        (m) =>
            m.username.toLowerCase().contains(needle) ||
            m.displayName.toLowerCase().contains(needle),
      )
      .toList();
}

/// [members] newest account first.
///
/// Ties break on username so the order is total: several accounts registered
/// in the same millisecond is exactly what a scripted wave looks like, and a
/// list that reshuffles between rebuilds is unusable for picking them out.
List<api.UserProfile> membersByJoinedNewestFirst(
  List<api.UserProfile> members,
) {
  final sorted = [...members];
  sorted.sort((a, b) {
    final byTime = b.createdAt.compareTo(a.createdAt);
    if (byTime != 0) return byTime;
    return a.username.toLowerCase().compareTo(b.username.toLowerCase());
  });
  return sorted;
}
