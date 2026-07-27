// SPDX-License-Identifier: Apache-2.0
/// Renders a poll message: the question, each option with its live tally,
/// and a tap to vote. Voting is refused server-side once the poll is
/// closed regardless of what this renders, so [poll]'s own `closed` flag
/// (never the client's clock) is what disables the tap here too.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

class PollView extends StatelessWidget {
  const PollView({super.key, required this.poll, required this.onVote});

  final api.Poll poll;
  final ValueChanged<int> onVote;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final canVote = !poll.closed;

    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      padding: const EdgeInsets.all(AppSpacing.s12),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            poll.question,
            style: AppText.body.copyWith(
              color: tokens.textPrimary,
              fontWeight: AppWeights.semi,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          for (final option in poll.options) ...[
            _PollOptionRow(
              option: option,
              totalVotes: poll.totalVotes,
              selected: poll.votedOption == option.position,
              onTap: canVote ? () => onVote(option.position) : null,
            ),
            const SizedBox(height: AppSpacing.s4),
          ],
          Text(
            '${poll.totalVotes} vote${poll.totalVotes == 1 ? '' : 's'}'
            '${poll.closed ? ' - closed' : ''}',
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PollOptionRow extends StatelessWidget {
  const _PollOptionRow({
    required this.option,
    required this.totalVotes,
    required this.selected,
    required this.onTap,
  });

  final api.PollOption option;
  final int totalVotes;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final fraction = totalVotes == 0 ? 0.0 : option.votes / totalVotes;
    final percent = (fraction * 100).round();

    return Semantics(
      button: onTap != null,
      selected: selected,
      label:
          '${option.label}, $percent percent, ${option.votes} votes'
          '${selected ? ', your vote' : ''}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 34,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? tokens.accentFill : tokens.borderSubtle,
            ),
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Stack(
            children: [
              FractionallySizedBox(
                widthFactor: fraction.clamp(0, 1),
                child: Container(
                  color: selected ? tokens.accentSoft : tokens.surfaceSunken,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option.label,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.ui.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: selected
                              ? AppWeights.semi
                              : AppWeights.regular,
                        ),
                      ),
                    ),
                    Text(
                      '$percent%',
                      style: AppText.caption.copyWith(
                        color: tokens.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
