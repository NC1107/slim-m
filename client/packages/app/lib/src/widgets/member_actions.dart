// SPDX-License-Identifier: Apache-2.0
/// Acting on one member, from the row's own context menu.
///
/// Split out of `member_pane.dart`, for the same reason
/// `channel_message_actions.dart` was split out of `channel_screen.dart`:
/// both need a [BuildContext] to put a snackbar in front of somebody, which
/// is not something the pure roster/presence layer in
/// `providers/member_presence.dart` needs at all.
///
/// The actions themselves live in `safety_actions.dart` and are shared with the
/// message context menu; these two are the member row's names for them.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;

import 'safety_actions.dart';

/// Files a report against a member, from the row's context menu.
///
/// Takes a [ProviderContainer] rather than a [WidgetRef] for the same reason
/// `safety_actions.dart` does: the caller dismisses the popover this is
/// offered from before the request answers.
Future<void> reportMember(
  BuildContext context,
  ProviderContainer container,
  api.UserProfile profile,
) => fileReport(
  context,
  container,
  subject: api.ReportSubject.user,
  subjectId: profile.id,
  subjectLabel: 'this member',
);

/// Blocks a member from the row's context menu.
Future<void> blockMember(
  BuildContext context,
  ProviderContainer container,
  api.UserProfile profile,
) => blockUser(context, container, profile.id);

/// Unblocks a member from the row's context menu.
Future<void> unblockMember(
  BuildContext context,
  ProviderContainer container,
  api.UserProfile profile,
) => unblockUser(context, container, profile.id);
