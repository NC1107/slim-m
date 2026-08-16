// SPDX-License-Identifier: Apache-2.0
/// The member pane's search box and its sort toggle.
///
/// Kept beside the pane rather than inside it: `member_pane.dart` was already
/// at the review budget, and what this holds is a small piece of view state
/// with no bearing on how a row draws.
///
/// Both controls are local and client-side. The roster is fetched whole
/// already and a profile carries the join time, so neither costs a request -
/// which is what makes a search box worth having here rather than a route.
///
/// The state is `autoDispose` and therefore resets when the pane closes. That
/// is deliberate: a filter left applied is a roster that silently lies about
/// who is in the Space, and the pane is the one surface people read to answer
/// exactly that.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/member_search.dart';

/// What the member pane's search box currently holds.
final memberQueryProvider = StateProvider.autoDispose<String>((ref) => '');

/// How the member pane is ordering the roster.
final memberSortProvider = StateProvider.autoDispose<MemberSort>(
  (ref) => MemberSort.presence,
);

class MemberPaneSearch extends ConsumerStatefulWidget {
  const MemberPaneSearch({super.key});

  @override
  ConsumerState<MemberPaneSearch> createState() => _MemberPaneSearchState();
}

class _MemberPaneSearchState extends ConsumerState<MemberPaneSearch> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final sort = ref.watch(memberSortProvider);
    final byJoined = sort == MemberSort.joined;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s8,
        vertical: AppSpacing.s8,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Row(
        children: [
          Expanded(
            child: AppInput(
              controller: _controller,
              placeholder: 'Find a member',
              icon: Icon(
                AppIcons.search,
                size: AppSizes.icon16,
                color: tokens.textSecondary,
              ),
              onChanged: (value) =>
                  ref.read(memberQueryProvider.notifier).state = value,
            ),
          ),
          const SizedBox(width: AppSpacing.s4),
          AppIconButton(
            icon: AppIcons.clock,
            semanticLabel: byJoined
                ? 'Sorting by most recently joined'
                : 'Sort by most recently joined',
            tooltip: byJoined
                ? 'Sorting by most recently joined'
                : 'Sort by most recently joined',
            active: byJoined,
            onPressed: () => ref.read(memberSortProvider.notifier).state =
                byJoined ? MemberSort.presence : MemberSort.joined,
          ),
        ],
      ),
    );
  }
}
