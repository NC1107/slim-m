// SPDX-License-Identifier: Apache-2.0
/// Who can join this Space: the one Space setting with no screen of its own.
///
/// Rendered as a [ListTile] rather than [SettingsSelectRow]'s own
/// [AppListRow] presentation, to match the plain [ListTile] rows either side
/// of it on [SpaceSettingsScreen] (leading icon, larger type, more height);
/// the current value still shows, as a subtitle, since seeing it without
/// opening the row is the point.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import 'run_guarded.dart';
import 'settings_select_row.dart';

final joinPolicyProvider = FutureProvider.autoDispose<api.JoinPolicy>(
  (ref) => ref.watch(apiProvider).spaceJoinPolicy(),
);

const _choices = [
  SettingsChoice(value: api.JoinPolicy.invite, label: 'People with an invite'),
  SettingsChoice(value: api.JoinPolicy.open, label: 'Anyone with the address'),
];

String _labelFor(api.JoinPolicy policy) => _choices
    .firstWhere(
      (choice) => choice.value == policy,
      orElse: () => _choices.first,
    )
    .label;

class JoinPolicyRow extends ConsumerStatefulWidget {
  const JoinPolicyRow({super.key});

  @override
  ConsumerState<JoinPolicyRow> createState() => _JoinPolicyRowState();
}

class _JoinPolicyRowState extends ConsumerState<JoinPolicyRow>
    with GuardedActionState<JoinPolicyRow> {
  bool _saving = false;

  Future<void> _set(api.JoinPolicy policy) async {
    setState(() => _saving = true);
    final ok = await guard(
      whatFailed: 'change who can join',
      action: () => ref.read(apiProvider).setSpaceJoinPolicy(policy),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) ref.invalidate(joinPolicyProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final policy = ref.watch(joinPolicyProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        policy.when(
          loading: () => const ListTile(
            leading: Icon(AppIcons.members),
            title: Text('Who can join'),
            subtitle: Text('Loading…'),
          ),
          // A fixed sentence, never the exception itself: a raw parse error
          // was rendering Dart type names into this row, which reads as a
          // crash and tells nobody anything actionable.
          error: (e, _) => ListTile(
            leading: const Icon(AppIcons.members),
            title: const Text('Who can join'),
            subtitle: Text(
              'Could not load who can join.',
              style: TextStyle(color: tokens.dangerText),
            ),
            trailing: TextButton(
              onPressed: () => ref.invalidate(joinPolicyProvider),
              child: const Text('Retry'),
            ),
          ),
          data: (current) => ListTile(
            leading: const Icon(AppIcons.members),
            title: const Text('Who can join'),
            subtitle: Text(
              _labelFor(current),
              style: TextStyle(color: tokens.textSecondary),
            ),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: _saving ? null : () => _open(context, current),
          ),
        ),
        if (actionError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s16,
              0,
              AppSpacing.s16,
              AppSpacing.s8,
            ),
            child: AppErrorState(
              message: actionError!,
              onDismiss: clearActionError,
            ),
          ),
      ],
    );
  }

  Future<void> _open(BuildContext context, api.JoinPolicy current) async {
    final chosen = await SettingsSelectRow.pick<api.JoinPolicy>(
      context,
      title: 'Who can create an account',
      value: current,
      choices: _choices,
    );
    if (chosen != null && chosen != current) await _set(chosen);
  }
}
