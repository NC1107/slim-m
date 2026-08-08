// SPDX-License-Identifier: Apache-2.0
/// The rail header's chevron: Space settings, plus channel creation
/// (backlog item 55 - creation moved here from a header "+" that had no
/// label explaining what it was for).
///
/// Its own file so `channel_rail_frame.dart` carries the rail's fixed bars
/// rather than also carrying an overlay menu's wiring.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_design_system/design_system.dart';

import '../permissions.dart';
import '../providers/admin_providers.dart';
import '../routing/routes.dart';
import 'context_menu_focus.dart';
import 'create_channel_sheet.dart';
import 'space_settings_section.dart';

/// Hidden entirely for a caller holding none of [spaceSettingsReachable]'s
/// gating bits: its one item at minimum is Space settings, and a member who
/// cannot reach that screen must not be offered a menu that opens onto it
/// empty. "Add channel" and "Add category" are gated separately, on
/// [Perm.manageChannels] specifically - the same bit the rail's own channel
/// rows already require to be dragged and reordered - so a moderator who can
/// see reports but not manage channels sees the menu without those two items
/// rather than either item 403ing.
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
    final canManageChannels = permissions.hasPermission(Perm.manageChannels);

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
              // The same keyboard route the context menus already earned:
              // Tab reaches every item once open, and Escape closes it.
              child: ContextMenuKeyboardScope(
                onDismiss: _controller.hide,
                child: AppMenu(
                  width: 200,
                  children: [
                    if (canManageChannels) ...[
                      AppMenuItem(
                        label: 'Add channel',
                        leading: AppIcons.add,
                        onTap: () {
                          _controller.hide();
                          showCreateChannelSheet(
                            context,
                            initialKind: 'text',
                          );
                        },
                      ),
                      AppMenuItem(
                        label: 'Add category',
                        leading: AppIcons.add,
                        onTap: () {
                          _controller.hide();
                          context.push(Routes.adminCategories);
                        },
                      ),
                    ],
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
