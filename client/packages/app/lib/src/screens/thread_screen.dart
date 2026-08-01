// SPDX-License-Identifier: Apache-2.0
/// The thread panel: a message's hidden sub-channel, reached by "Reply in
/// thread" from the message context menu.
///
/// Reuses [ChannelScreen] wholesale for the transcript and the composer - a
/// thread is an ordinary channel with `parentMessageId` set
/// (docs/decisions/0005-threads.md), so nothing here needs to know how to
/// render a message or send one; that is [ChannelScreen]'s job already, and
/// it already tolerates a channel with no rail entry the way a DM does.
library;

import 'package:flutter/material.dart';

import 'channel_screen.dart';

class ThreadScreen extends StatelessWidget {
  const ThreadScreen({required this.channelId, super.key});

  final String channelId;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Thread')),
    body: ChannelScreen(channelId: channelId),
  );
}
