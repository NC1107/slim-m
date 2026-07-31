// SPDX-License-Identifier: Apache-2.0
/// The rail's always-present entry point to the caller's own personal
/// space. Split out of `channel_rail_sections.dart` to keep that file under
/// the review budget once this grew a guarded async open.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/dms.dart';
import '../providers/providers.dart';
import '../routing/routes.dart';
import 'run_guarded.dart';

/// Reachable before the channel exists at all - the first tap opens it -
/// and renders identically after, so the row never moves once it does.
class PersonalSpaceRow extends ConsumerStatefulWidget {
  const PersonalSpaceRow({
    super.key,
    required this.channel,
    required this.selected,
  });

  /// The local channel row already synced for this personal space, or null
  /// before it has ever been opened on any device.
  final Channel? channel;
  final bool selected;

  @override
  ConsumerState<PersonalSpaceRow> createState() => _PersonalSpaceRowState();
}

class _PersonalSpaceRowState extends ConsumerState<PersonalSpaceRow>
    with GuardedActionState<PersonalSpaceRow> {
  /// Guards against a second tap firing a second `POST /dms/self` while the
  /// first is still in flight - there is no request to dedupe against yet,
  /// unlike an already-open personal space, which just navigates.
  bool _opening = false;

  Future<void> _open() async {
    final existing = widget.channel;
    if (existing != null) {
      context.go(Routes.channel(existing.id));
      return;
    }
    final selfId = ref.read(sessionProvider).tokens?.userId;
    if (selfId == null) return;
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _opening = true);
    String? channelId;
    final ok = await guard(
      whatFailed: 'open your personal space',
      action: () async {
        channelId = await openDirectMessage(container, selfId);
      },
    );
    if (!mounted) return;
    setState(() => _opening = false);
    if (ok && channelId != null) context.go(Routes.channel(channelId!));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final existing = widget.channel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppListRow(
          label: personalSpaceName,
          selected: widget.selected,
          unread: existing != null && existing.cursor > existing.lastReadSeq,
          // Matches AppAvatar(size: 20)'s 20x20 footprint; a bare 16px icon left the label 4dp misaligned.
          leading: SizedBox(
            width: 20,
            height: 20,
            child: Center(
              child: Icon(
                AppIcons.notebook,
                size: AppSizes.icon16,
                color: widget.selected ? tokens.accent : tokens.textSecondary,
              ),
            ),
          ),
          onTap: _opening ? null : _open,
        ),
        if (actionError != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s8,
              vertical: AppSpacing.s4,
            ),
            child: AppErrorState(
              message: actionError!,
              onDismiss: clearActionError,
            ),
          ),
      ],
    );
  }
}
