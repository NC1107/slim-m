// SPDX-License-Identifier: Apache-2.0
/// The caller's own status: the four choices, the call that applies one, and
/// the rail footer's avatar button that opens them as a menu.
///
/// Lives beside the rail rather than inside `channel_rail_frame.dart` so that
/// file stays under this repo's 300-line review budget.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../providers/presence_controller.dart';
import '../providers/providers.dart';
import 'user_avatar.dart';

/// Every visibility a caller may choose, each with the label it is offered
/// under and the silhouette [AppStatusDot] draws for it.
///
/// `hidden` is appear-offline, and it is deliberately one tap from the avatar
/// rather than buried in settings: it is the only choice here with a privacy
/// consequence, so it has to be the easiest one to reach in a hurry.
const presenceOptions = <(api.PresenceVisibility, String, AppPresence)>[
  (api.PresenceVisibility.online, 'Online', AppPresence.online),
  (api.PresenceVisibility.away, 'Away', AppPresence.away),
  (api.PresenceVisibility.dnd, 'Do not disturb', AppPresence.dnd),
  (api.PresenceVisibility.hidden, 'Appear offline', AppPresence.hidden),
];

/// The rail footer's status line and dot for a chosen [visibility]: the same
/// label the menu offers, lowercased to match the footer's register.
///
/// A null [visibility] is "no choice known this session", so the line reports
/// this device's connection, the way the connecting and offline cases already
/// do, instead of claiming a visibility it cannot read back. Saying "online"
/// there would tell someone who chose appear-offline last week that they are
/// visible; see [presenceVisibilityDisplayProvider].
(String, AppPresence) presenceDisplayOf(api.PresenceVisibility? visibility) {
  if (visibility == null) return ('connected', AppPresence.online);
  final option =
      presenceOptions.firstWhere((option) => option.$1 == visibility);
  return (option.$2.toLowerCase(), option.$3);
}

/// Sets the caller's own visibility.
///
/// The local echo is set first so the menu and the footer update on the tap
/// rather than on the round trip; see [presenceVisibilityDisplayProvider] for
/// why that echo exists at all. A failure is surfaced rather than swallowed,
/// because a silently unchanged appear-offline is the one outcome here a user
/// must never be left believing.
Future<void> applyPresenceVisibility(
  BuildContext context,
  WidgetRef ref,
  api.PresenceVisibility visibility,
) async {
  ref.read(presenceVisibilityDisplayProvider.notifier).state = visibility;
  try {
    await ref.read(apiProvider).setPresenceVisibility(visibility);
  } on api.ApiException catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Could not update presence. ${e.message}')),
    );
  }
}

/// The rail footer's avatar, as a tap target that opens the status menu
/// upward off the bottom bar.
class PresenceMenuButton extends ConsumerStatefulWidget {
  const PresenceMenuButton({super.key, required this.presence});

  /// The dot drawn on the avatar. The footer derives it, because a device
  /// that is not connected reports that instead of the chosen status.
  final AppPresence presence;

  @override
  ConsumerState<PresenceMenuButton> createState() => _PresenceMenuButtonState();
}

class _PresenceMenuButtonState extends ConsumerState<PresenceMenuButton> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final selected = ref.watch(presenceVisibilityDisplayProvider);

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        // Read here rather than in the builder: the overlay child builds
        // under its own element, outside this widget's build phase.
        overlayChildBuilder: (_) => _buildMenu(tokens, selected),
        // A 28pt avatar is well under the touch minimum, so the tap area is
        // grown around it rather than the glyph being grown to match.
        child: Semantics(
          button: true,
          label: 'Change your status',
          onTap: _controller.toggle,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _controller.toggle,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AppSizes.rowTouch,
                minHeight: AppSizes.rowTouch,
              ),
              child: Center(
                child: UserAvatar(
                  userId: me.valueOrNull?.id,
                  avatarUpdatedAt: me.valueOrNull?.avatarUpdatedAt,
                  name: me.valueOrNull?.displayName ?? '',
                  size: 28,
                  status: widget.presence,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// [selected] is null until a choice is made in this session, and then no
  /// item is marked current: ticking one would assert a stored value this
  /// client has no way to read back.
  Widget _buildMenu(AppTokens tokens, api.PresenceVisibility? selected) {
    // Positioned so the follower sizes to its content: an overlay child is
    // otherwise laid out against the whole screen, which a Column fills.
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: const Offset(0, -4),
        child: TapRegion(
          onTapOutside: (_) => _controller.hide(),
          child: AppMenu(
            width: 220,
            children: [
              const AppMenuLabel('Status'),
              for (final (visibility, label, presence) in presenceOptions)
                AppMenuItem(
                  label: label,
                  selected: visibility == selected,
                  // surfaceRaised, not the default, because the dnd notch and
                  // the appear-offline slash punch their mark in this colour.
                  trailing: AppStatusDot(
                    status: presence,
                    backgroundColor: tokens.surfaceRaised,
                  ),
                  onTap: () {
                    _controller.hide();
                    unawaited(
                        applyPresenceVisibility(context, ref, visibility));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
