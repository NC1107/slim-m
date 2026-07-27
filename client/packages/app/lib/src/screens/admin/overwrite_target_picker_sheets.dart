// SPDX-License-Identifier: Apache-2.0
/// The role and member picker sheets [ChannelOverwritesScreen] opens for
/// `_pickTarget`, split out purely to keep that file under the line budget.
///
/// Both watch their provider from inside the sheet rather than being handed
/// a pre-read list: an autoDispose `FutureProvider` read once with
/// `ref.read` outside a listener registers no subscriber, so it can be
/// (and reliably is) torn down mid-fetch, leaving the sheet permanently
/// empty with no spinner and no error. Watching keeps the provider alive
/// for exactly as long as the sheet is open, the same shape
/// `role_assign_sheet.dart` already uses for its member list.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../../providers/admin_providers.dart';
import '../../widgets/member_pane.dart' show membersProvider;

/// Bounded height so a loading spinner or an error has somewhere to center;
/// a `ListView(shrinkWrap: true)` has no intrinsic height before data
/// arrives.
const _pickerSheetHeightFraction = 0.6;

class RolePickerSheet extends ConsumerWidget {
  const RolePickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(rolesProvider);
    return SizedBox(
      height: MediaQuery.of(context).size.height * _pickerSheetHeightFraction,
      child: roles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _PickerError(
          message: 'Could not load roles. $e',
          onRetry: () => ref.invalidate(rolesProvider),
        ),
        data: (list) => list.isEmpty
            ? const _PickerEmpty(message: 'No roles yet.')
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final role = list[i];
                  return ListTile(
                    leading: const Icon(AppIcons.shield),
                    title: Text(role.name),
                    onTap: () => Navigator.of(context).pop(role),
                  );
                },
              ),
      ),
    );
  }
}

class MemberPickerSheet extends ConsumerWidget {
  const MemberPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider);
    return SizedBox(
      height: MediaQuery.of(context).size.height * _pickerSheetHeightFraction,
      child: members.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _PickerError(
          message: 'Could not load members. $e',
          onRetry: () => ref.invalidate(membersProvider),
        ),
        data: (list) => list.isEmpty
            ? const _PickerEmpty(message: 'No members yet.')
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, i) {
                  final member = list[i];
                  return ListTile(
                    leading: const Icon(AppIcons.account),
                    title: Text(member.displayName),
                    subtitle: Text('@${member.username}'),
                    onTap: () => Navigator.of(context).pop(member),
                  );
                },
              ),
      ),
    );
  }
}

class _PickerError extends StatelessWidget {
  const _PickerError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              style: TextStyle(color: tokens.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _PickerEmpty extends StatelessWidget {
  const _PickerEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Center(
      child: Text(message, style: TextStyle(color: tokens.textSecondary)),
    );
  }
}
