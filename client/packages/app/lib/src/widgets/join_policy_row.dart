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

import '../diagnostics/debug_log.dart';
import '../providers/providers.dart';
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

class _JoinPolicyRowState extends ConsumerState<JoinPolicyRow> {
  bool _saving = false;

  Future<void> _set(api.JoinPolicy policy) async {
    setState(() => _saving = true);
    try {
      await ref.read(apiProvider).setSpaceJoinPolicy(policy);
      if (!mounted) return;
      ref.invalidate(joinPolicyProvider);
    } on api.ApiException catch (e) {
      ref
          .read(debugLogProvider.notifier)
          .record('space', 'Could not change who can join', detail: e);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final policy = ref.watch(joinPolicyProvider);

    return policy.when(
      loading: () => const ListTile(
        leading: Icon(AppIcons.invite),
        title: Text('Who can join'),
        subtitle: Text('Loading…'),
      ),
      error: (e, _) => ListTile(
        leading: const Icon(AppIcons.invite),
        title: const Text('Who can join'),
        subtitle: Text(
          'Could not load. $e',
          style: TextStyle(color: tokens.dangerText),
        ),
        trailing: TextButton(
          onPressed: () => ref.invalidate(joinPolicyProvider),
          child: const Text('Retry'),
        ),
      ),
      data: (current) => ListTile(
        leading: const Icon(AppIcons.invite),
        title: const Text('Who can join'),
        subtitle: Text(
          _labelFor(current),
          style: TextStyle(color: tokens.textSecondary),
        ),
        trailing: const Icon(AppIcons.chevronRight),
        onTap: _saving ? null : () => _open(context, current),
      ),
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
