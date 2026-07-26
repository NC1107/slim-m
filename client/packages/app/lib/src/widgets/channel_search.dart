// SPDX-License-Identifier: Apache-2.0
/// The inline panel the channel header's search toggle reveals: a query
/// field over the real full-text search endpoint, and its results in place
/// of the live message list while open.
library;

import 'package:flutter/material.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import 'message_text.dart';

class ChannelSearchBar extends StatelessWidget {
  const ChannelSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s16, vertical: AppSpacing.s8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: AppInput(
        controller: controller,
        placeholder: 'Search this channel',
        icon: Icon(AppIcons.search,
            size: AppSizes.icon16, color: tokens.textSecondary),
        autofocus: true,
        onChanged: onChanged,
      ),
    );
  }
}

class ChannelSearchResults extends StatelessWidget {
  const ChannelSearchResults({
    super.key,
    required this.results,
    required this.knownUsernames,
  });

  final List<api.Message> results;
  final Set<String> knownUsernames;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    if (results.isEmpty) {
      return Center(
        child:
            Text('No matches.', style: TextStyle(color: tokens.textSecondary)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.s16),
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s12),
      itemBuilder: (context, i) {
        final message = results[i];
        final name = message.authorDisplayName ??
            (message.authorId == null ? 'Deleted user' : 'Unknown');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: AppText.ui.copyWith(
                  color: tokens.textPrimary, fontWeight: AppWeights.semi),
            ),
            const SizedBox(height: AppSpacing.s4),
            MessageBody(
                content: message.content, knownUsernames: knownUsernames),
          ],
        );
      },
    );
  }
}
