// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// "What people in this Space see when they open your card" - the member
/// card's own header, about and roles/join sections, reused verbatim rather
/// than redrawn, so this can never drift from what the real card shows.
///
/// Built from [userProfileProvider], not [meProvider]: the public shape is
/// what the preview promises to be, and it is the one place this account's
/// own role chips are available at all - `Me` carries no roles. It updates
/// once a field's own save round-trip lands (each field here saves on blur
/// or on tap), not on every keystroke; nothing else in this app previews a
/// field before it is actually saved.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import '../providers/user_profiles.dart';
import 'member_profile_identity.dart';
import 'member_profile_sections.dart';
import 'settings_section_header.dart';

class SettingsProfilePreview extends ConsumerWidget {
  const SettingsProfilePreview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final me = ref.watch(meProvider).valueOrNull;
    final profile = me == null
        ? null
        : ref.watch(userProfileProvider(me.id)).valueOrNull;

    if (profile == null) return const SizedBox.shrink();

    return SettingsSectionCard(
      title: 'How others see you',
      children: [
        Container(
          margin: const EdgeInsets.all(AppSpacing.s8),
          decoration: BoxDecoration(
            border: Border.all(color: tokens.borderSubtle),
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MemberProfileHeader(
                profile: profile,
                status: AppPresence.online,
                isSelf: true,
                inCallTogether: false,
              ),
              if (profile.about case final about? when about.isNotEmpty)
                MemberProfileAbout(about: about),
              MemberProfileRolesAndJoin(
                roles: profile.roles,
                createdAt: profile.createdAt,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
