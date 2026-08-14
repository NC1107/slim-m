// SPDX-License-Identifier: Apache-2.0
/// The one affordance that opens a channel's canvas.
///
/// It sits in a voice channel's header, at every width, rather than only
/// inside a live call: a call needs a configured SFU and somebody already in
/// it, so an in-call-only entry would leave the product's signature feature
/// invisible whenever the room is empty.
///
/// Voice channels only, by owner decision (backlog, 2026-08-13, "there also
/// should not be a canvas in text channels, only voice channels"). This
/// deliberately reverses what this comment used to argue: that a text
/// channel needs it too, because bootstrap seeds one text channel and
/// `SLIMM_LIVEKIT_URL` is optional, so a fresh self-host with no voice
/// channel now cannot reach the canvas at all. That consequence is real and
/// accepted rather than overlooked - the canvas belongs to talking together,
/// and a deployment that wants one creates a voice channel.
///
/// The kind arrives as [isVoice] from the header that builds this, rather
/// than being read back out of the local store: every call site already
/// knows it, and a store round trip would make an affordance appear a frame
/// or two late on a screen that has the answer synchronously. It subsumes
/// the DM case for free - a DM is not a voice channel, and its base
/// permissions never include `USE_CANVAS` (`store/dms.rs`'s `DM_BASE`, and
/// DMs skip the overwrite evaluator that could otherwise grant it), so every
/// canvas route 403s there regardless.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import 'canvas_pane.dart';

class CanvasOpenButton extends ConsumerWidget {
  const CanvasOpenButton({
    super.key,
    required this.channelId,
    required this.isVoice,
  });

  final String channelId;

  /// Whether this channel is a voice channel, the only kind that has a canvas.
  final bool isVoice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isVoice) return const SizedBox.shrink();
    final open = ref.watch(canvasOpenProvider) == channelId;
    return _button(ref, open);
  }

  Widget _button(WidgetRef ref, bool open) => AppIconButton(
    icon: AppIcons.canvas,
    semanticLabel: 'Open canvas',
    active: open,
    onPressed: () =>
        ref.read(canvasOpenProvider.notifier).state = open ? null : channelId,
  );
}
