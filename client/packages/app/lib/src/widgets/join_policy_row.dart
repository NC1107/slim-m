// SPDX-License-Identifier: Apache-2.0
/// Who can join this Space: the one Space setting with no screen of its own.
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
      data: (current) => SettingsSelectRow<api.JoinPolicy>(
        label: 'Who can join',
        sheetTitle: 'Who can create an account',
        value: current,
        onChanged: _saving ? (_) {} : _set,
        choices: const [
          SettingsChoice(
            value: api.JoinPolicy.invite,
            label: 'People with an invite',
          ),
          SettingsChoice(
            value: api.JoinPolicy.open,
            label: 'Anyone with the address',
          ),
        ],
      ),
    );
  }
}
