// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The one affordance that starts or opens a DM's call.
///
/// Self-gated on the channel's own kind rather than a caller-supplied flag,
/// the same shape `CanvasOpenButton` could have used: a header that always
/// includes this renders nothing for a text or voice channel, or for a
/// personal space, where calling yourself is not a call.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/channel_by_id_provider.dart';
import 'dm_call_pane.dart';

class DmCallButton extends ConsumerWidget {
  const DmCallButton({super.key, required this.channelId});

  final String channelId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channel = ref.watch(channelByIdProvider(channelId)).valueOrNull;
    if (channel == null || channel.kind != 'dm' || channel.isPersonalSpace) {
      return const SizedBox.shrink();
    }
    final open = ref.watch(dmCallOpenProvider) == channelId;
    return AppIconButton(
      icon: AppIcons.startCall,
      semanticLabel: 'Call',
      tooltip: 'Call',
      active: open,
      onPressed: () =>
          ref.read(dmCallOpenProvider.notifier).state = open ? null : channelId,
    );
  }
}
