// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The profile-first content between the header and the actions: an about
/// line, role chips, and a join date. Split out of `member_profile_sections
/// .dart` to keep that file under the review budget.
///
/// Each piece is *absent* rather than present-and-empty, the same rule the
/// rest of the card follows: an account with no about line shows no about
/// row at all, not an empty one.
library;

import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

const List<String> _shortMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "joined Mar 2026", from Unix milliseconds.
String formatJoinDate(int createdAtMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(createdAtMs);
  return 'joined ${_shortMonths[dt.month - 1]} ${dt.year}';
}

/// A short "about" paragraph under the status line.
class MemberProfileAbout extends StatelessWidget {
  const MemberProfileAbout({super.key, required this.about});

  final String about;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        0,
        AppSpacing.s12,
        AppSpacing.s8,
      ),
      child: Text(
        about,
        style: AppText.caption.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}

/// Role chips (visible to everyone, per the design - editing them is a
/// Moderate-only affair) beside the join date.
class MemberProfileRolesAndJoin extends StatelessWidget {
  const MemberProfileRolesAndJoin({
    super.key,
    required this.roles,
    required this.createdAt,
  });

  final List<String> roles;
  final int createdAt;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s12,
        0,
        AppSpacing.s12,
        AppSpacing.s12,
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.s8,
        runSpacing: AppSpacing.s4,
        children: [
          for (final role in roles) _RoleChip(label: role),
          Text(
            formatJoinDate(createdAt),
            style: AppText.micro.copyWith(color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Mono 10, outlined - the design's own wording for a role chip. Distinct
/// from [AppBadge]'s single-role badge in the header of the old layout: this
/// one shows every role a member holds, not just the first.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s8),
      height: 20,
      // No Container.alignment: with no explicit width it expands to fill the parent.
      decoration: BoxDecoration(
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(AppRadii.control),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          style: AppText.code.copyWith(color: tokens.textSecondary, fontSize: 10),
        ),
      ),
    );
  }
}
