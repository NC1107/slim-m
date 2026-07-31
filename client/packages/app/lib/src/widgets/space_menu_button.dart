// SPDX-License-Identifier: Apache-2.0
/// The rail header's chevron: today, a way to Space settings.
///
/// Its own file so `channel_rail_frame.dart` carries the rail's fixed bars
/// rather than also carrying an overlay menu's wiring.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/admin_providers.dart';
import '../routing/routes.dart';
import 'space_settings_section.dart';

/// Hidden entirely for a caller holding none of [spaceSettingsReachable]'s
/// gating bits: its one item today is Space settings, and a member who
/// cannot reach that screen must not be offered a menu that opens onto it
/// empty. A future item unrelated to permission would need this reconsidered.
class SpaceMenuButton extends ConsumerStatefulWidget {
  const SpaceMenuButton({super.key});

  @override
  ConsumerState<SpaceMenuButton> createState() => _SpaceMenuButtonState();
}

class _SpaceMenuButtonState extends ConsumerState<SpaceMenuButton> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final permissions = ref.watch(myPermissionsProvider);
    if (!spaceSettingsReachable(permissions)) return const SizedBox.shrink();

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        // Positioned so the follower sizes to its content, not the whole screen a Column would otherwise fill it against.
        overlayChildBuilder: (context) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 4),
            child: TapRegion(
              onTapOutside: (_) => _controller.hide(),
              child: AppMenu(
                width: 200,
                children: [
                  AppMenuItem(
                    label: 'Space settings',
                    leading: AppIcons.settings,
                    onTap: () {
                      _controller.hide();
                      context.push(Routes.spaceSettings);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        child: AppIconButton(
          icon: AppIcons.chevronDown,
          semanticLabel: 'Space menu',
          onPressed: _controller.toggle,
        ),
      ),
    );
  }
}
