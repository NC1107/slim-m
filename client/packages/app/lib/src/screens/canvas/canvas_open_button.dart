// SPDX-License-Identifier: Apache-2.0
/// The one affordance that opens a channel's canvas.
///
/// It sits in every channel header, text and voice, at every width, rather
/// than only inside a live call. A call needs a configured SFU and a voice
/// channel, and a fresh self-host has neither - bootstrap seeds one text
/// channel and `SLIMM_LIVEKIT_URL` is optional - so an in-call-only entry
/// would leave the product's signature feature invisible on most deployments
/// while the endpoint behind it works fine. That is the exact shape of gap
/// this repo has shipped three times before.
///
/// Self-gated on the channel's own kind, the shape `DmCallButton`'s doc
/// comment already names: a DM's base permissions never include
/// `USE_CANVAS` (`store/dms.rs`'s `DM_BASE`, and DMs skip the overwrite
/// evaluator that could otherwise grant it), so every canvas route 403s
/// there unconditionally - the button hides rather than offering an
/// affordance guaranteed to fail.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../../providers/providers.dart';
import 'canvas_pane.dart';

class CanvasOpenButton extends ConsumerWidget {
  const CanvasOpenButton({super.key, required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(canvasOpenProvider) == channelId;
    final storeAsync = ref.watch(storeProvider);
    return storeAsync.maybeWhen(
      // Unresolved reads as available - see this class's own doc comment.
      orElse: () => _button(ref, open),
      data: (store) => StreamBuilder<Channel?>(
        stream: store.watchChannelRow(channelId),
        builder: (context, snapshot) => snapshot.data?.kind == 'dm'
            ? const SizedBox.shrink()
            : _button(ref, open),
      ),
    );
  }

  Widget _button(WidgetRef ref, bool open) => AppIconButton(
    icon: AppIcons.canvas,
    semanticLabel: 'Open canvas',
    active: open,
    onPressed: () =>
        ref.read(canvasOpenProvider.notifier).state = open ? null : channelId,
  );
}
