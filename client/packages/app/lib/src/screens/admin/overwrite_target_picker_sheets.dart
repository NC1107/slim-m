// SPDX-License-Identifier: Apache-2.0
/// The channel, role and member picker sheets [ChannelOverwritesScreen]
/// opens, split out purely to keep that file under the line budget.
///
/// The role and member sheets watch their provider from inside the sheet
/// rather than being handed a pre-read list: an autoDispose `FutureProvider`
/// read once with `ref.read` outside a listener registers no subscriber, so
/// it can be (and reliably is) torn down mid-fetch, leaving the sheet
/// permanently empty with no spinner and no error. Watching keeps the
/// provider alive for exactly as long as the sheet is open, the same shape
/// `role_assign_sheet.dart` already uses for its member list.
///
/// The channel sheet takes an already-resolved list instead: its caller
/// awaits a one-shot `store.watchChannels().first` rather than a live
/// provider, so there is nothing here for it to watch.
///
/// Each carries a one-line heading, matching every sibling "choose one"
/// sheet (`camera_source_sheet.dart`, `screen_source_sheet.dart`) - these
/// three used to open straight into a bare row list, which read as a
/// floating pill on desktop and gave no on-screen confirmation of what was
/// being picked on phone.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_data/data.dart' show Channel;
import 'package:slimm_design_system/design_system.dart';

import '../../providers/admin_providers.dart';
import '../../providers/member_presence.dart' show membersProvider;

/// The ceiling a resolved list may grow to before it scrolls internally
/// rather than pushing the sheet past the window - never a size the sheet
/// is forced to regardless of how few rows there are; see
/// [_PickerList]'s own doc.
const _pickerListMaxHeightFraction = 0.6;

const _headingPadding = EdgeInsets.fromLTRB(
  AppSpacing.s16,
  0,
  AppSpacing.s16,
  AppSpacing.s12,
);

class ChannelPickerSheet extends StatelessWidget {
  const ChannelPickerSheet({super.key, required this.channels});

  final List<Channel> channels;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: _headingPadding,
            child: Text('Choose a channel', style: AppText.heading),
          ),
          _PickerList(
            children: [
              for (final c in channels)
                AppListRow(
                  leading: Icon(
                    c.kind == 'voice' ? AppIcons.voice : AppIcons.hash,
                  ),
                  label: c.name,
                  onTap: () => Navigator.of(context).pop(c),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class RolePickerSheet extends ConsumerWidget {
  const RolePickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roles = ref.watch(rolesProvider);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: _headingPadding,
            child: Text('Choose a role', style: AppText.heading),
          ),
          roles.when(
            loading: () => const _PickerLoading(),
            error: (e, _) => _PickerError(
              message: 'Could not load roles.',
              onRetry: () => ref.invalidate(rolesProvider),
            ),
            data: (list) => list.isEmpty
                ? const _PickerEmpty(message: 'No roles yet.')
                : _PickerList(
                    children: [
                      for (final role in list)
                        AppListRow(
                          leading: const Icon(AppIcons.shield),
                          label: role.name,
                          onTap: () => Navigator.of(context).pop(role),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class MemberPickerSheet extends ConsumerWidget {
  const MemberPickerSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(membersProvider);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: _headingPadding,
            child: Text('Choose a member', style: AppText.heading),
          ),
          members.when(
            loading: () => const _PickerLoading(),
            error: (e, _) => _PickerError(
              message: 'Could not load members.',
              onRetry: () => ref.invalidate(membersProvider),
            ),
            data: (list) => list.isEmpty
                ? const _PickerEmpty(message: 'No members yet.')
                : _PickerList(
                    children: [
                      for (final member in list)
                        AppListRow(
                          leading: const Icon(AppIcons.account),
                          label: member.displayName,
                          meta: '@${member.username}',
                          onTap: () => Navigator.of(context).pop(member),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// A resolved list of rows: sized to its content, up to
/// [_pickerListMaxHeightFraction] of the window, past which it scrolls
/// internally rather than growing further. `shrinkWrap: true` is what makes
/// two or three rows read as two or three rows rather than a card with most
/// of it empty - the previous fixed-fraction `SizedBox` forced this height
/// regardless of row count, the inverse of `avatar-crop-sheet`'s own
/// previously-shipped "too tall for the window" bug: this one was "too tall
/// for too little content."
class _PickerList extends StatelessWidget {
  const _PickerList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight:
          MediaQuery.sizeOf(context).height * _pickerListMaxHeightFraction,
    ),
    child: ListView(shrinkWrap: true, children: children),
  );
}

class _PickerLoading extends StatelessWidget {
  const _PickerLoading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(AppSpacing.s24),
    child: Center(child: CircularProgressIndicator()),
  );
}

class _PickerError extends StatelessWidget {
  const _PickerError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            style: AppText.body.copyWith(color: tokens.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s12),
          AppButton(
            label: 'Retry',
            variant: AppButtonVariant.ghost,
            onPressed: onRetry,
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s24),
      child: Center(
        child: Text(
          message,
          style: AppText.body.copyWith(color: tokens.textSecondary),
        ),
      ),
    );
  }
}
