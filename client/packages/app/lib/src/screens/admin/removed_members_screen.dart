// SPDX-License-Identifier: Apache-2.0
/// Who has been removed from this Space, and letting them back in.
///
/// The only place a removed member is still nameable: `GET /members` drops
/// them, which is the point of a removal, so without this screen the act
/// would be one-way through the interface even though the server makes it
/// reversible. Requires BAN_MEMBERS, the same bit that performs it.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../providers/admin_providers.dart';
import '../../providers/member_presence.dart' show membersProvider;
import '../../providers/providers.dart';
import '../../routing/routes.dart';
import '../../widgets/run_guarded.dart';
import '../settings_screen_scaffold.dart';

class RemovedMembersScreen extends ConsumerWidget {
  const RemovedMembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final removals = ref.watch(removedMembersProvider);

    return SettingsScreenScaffold(
      title: 'Removed members',
      backTooltip: 'Back to Space settings',
      backFallback: Routes.spaceSettings,
      scrollable: false,
      padding: EdgeInsets.zero,
      child: AppAsyncView<List<api.SpaceRemoval>>(
        value: AppAsyncState(data: removals.valueOrNull, error: removals.error),
        errorMessage: 'Could not load the removals.',
        onRetry: () => ref.invalidate(removedMembersProvider),
        isEmpty: (list) => list.isEmpty,
        emptyMessage: 'Nobody has been removed from this Space.',
        data: (context, list) => ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.s16),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s8),
          itemBuilder: (context, i) => _RemovalCard(removal: list[i]),
        ),
      ),
    );
  }
}

class _RemovalCard extends ConsumerStatefulWidget {
  const _RemovalCard({required this.removal});

  final api.SpaceRemoval removal;

  @override
  ConsumerState<_RemovalCard> createState() => _RemovalCardState();
}

class _RemovalCardState extends ConsumerState<_RemovalCard>
    with GuardedActionState<_RemovalCard> {
  bool _busy = false;

  Future<void> _restore() async {
    setState(() => _busy = true);
    final ok = await guard(
      whatFailed: 'let ${widget.removal.displayName} back in',
      action: () => ref.read(apiProvider).restoreMember(widget.removal.userId),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      ref.invalidate(removedMembersProvider);
      // The member list gains a row again, so it is stale too.
      ref.invalidate(membersProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final removal = widget.removal;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      removal.displayName,
                      style: AppText.body.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: AppWeights.semi,
                      ),
                    ),
                    Text(
                      '@${removal.username}',
                      style: AppText.caption.copyWith(
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppButton(
                label: 'Let back in',
                variant: AppButtonVariant.secondary,
                size: AppButtonSize.sm,
                onPressed: _busy ? null : _restore,
              ),
            ],
          ),
          if (removal.reason != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              removal.reason!,
              style: AppText.caption.copyWith(color: tokens.textSecondary),
            ),
          ],
          if (actionError != null) ...[
            const SizedBox(height: AppSpacing.s8),
            AppErrorState(message: actionError!, onDismiss: clearActionError),
          ],
        ],
      ),
    );
  }
}
