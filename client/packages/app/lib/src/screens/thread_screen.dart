// SPDX-License-Identifier: Apache-2.0
/// The thread panel: a message's hidden sub-channel, reached by "Reply in
/// thread" from the message context menu.
///
/// Reuses [ChannelScreen] wholesale for the transcript and the composer - a
/// thread is an ordinary channel with `parentMessageId` set
/// (docs/decisions/0005-threads.md), so nothing here needs to know how to
/// render a message or send one; that is [ChannelScreen]'s job already, and
/// it already tolerates a channel with no rail entry the way a DM does.
///
/// [ChannelScreen] builds its own `ChannelHeader` at any width that shows
/// both panes, which is correct for a channel opened through
/// `ConversationPane` and was wrong here: this bar is the only one a thread
/// gets at every width, so `channel_screen.dart` now skips its own header
/// for a thread channel specifically, rather than this screen forking it.
///
/// A thread is "sort of a temporary area to communicate" (the owner's own
/// words), so the header carries almost nothing: the back affordance and
/// the title, full stop. Everything `ChannelHeader` otherwise offers is
/// deliberately not wired in here at all, not merely hidden, and each was
/// weighed on its own rather than dropped as a block:
///
/// - Pin and the canvas are irrelevant to a side conversation this shallow -
///   a thread has no browsing surface of its own for a pinned set to be
///   rediscovered later, and a canvas button here was flagged as an unwanted
///   surface by the 2026-08-02 security review, not a thing anybody asked
///   for.
/// - The member-pane and channel-rail toggles are worse than irrelevant:
///   `memberPaneVisibleProvider` and `channelRailVisibleProvider`
///   (`widgets/member_pane.dart`, `widgets/channel_rail.dart`) are both bare
///   `StateProvider<bool>`, one flag for the whole app rather than one per
///   channel, and `HomeShell` reads them for whatever channel the router
///   currently has selected underneath this screen - not for the thread.
///   Wiring either button in here would flip UI chrome for the parent
///   channel a person cannot even see behind this overlay, which is exactly
///   the bug the owner reported: toggling the "member panel" control from
///   inside a thread opened the member pane for the channel behind it. Any
///   future overlay that reuses `ChannelHeader`'s controls needs to ask this
///   same question, since nothing about that provider shape stops it from
///   recurring.
/// - Search is the one kept, and only because it does not have that
///   shape: `channelSearchProvider` (`channel_search_controller.dart`) is a
///   `family` keyed by channel id, so a thread's own copy of it can only
///   ever open a search bar over the thread's own messages
///   (`thread_screen_test.dart` asserts the parent channel's copy of the
///   same provider is untouched). Kept scoped rather than dropped on the
///   same reasoning that would have dropped it: a control is fine here
///   exactly when it acts on the thread and nothing else.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../routing/close_screen.dart';
import '../routing/routes.dart';
import '../widgets/compact_channel_app_bar.dart' show ChannelSearchAction;
import 'channel_screen.dart';

class ThreadScreen extends StatelessWidget {
  const ThreadScreen({required this.channelId, super.key});

  final String channelId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      // The automatic back button is a Material glyph; BackToButton's is the Lucide one every other screen uses.
      leading: const BackToButton(
        tooltip: 'Back to the conversation',
        fallback: Routes.channels,
      ),
      title: const Text('Thread'),
      actions: [
        ChannelSearchAction(channelId: channelId),
        const SizedBox(width: AppSpacing.s8),
      ],
    ),
    body: ChannelScreen(channelId: channelId),
  );
}
