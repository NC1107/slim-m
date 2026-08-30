// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The caller's own status: the four choices, the call that applies one, and
/// the rail footer's avatar button that opens them as a menu or a sheet.
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
import 'context_menu_focus.dart';
import 'presence_status_field.dart';
import 'run_guarded.dart';
import 'status_editor_sheet.dart';
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
  final option = presenceOptions.firstWhere(
    (option) => option.$1 == visibility,
  );
  return (option.$2.toLowerCase(), option.$3);
}

/// Sets the caller's own visibility, and puts the echo back if the server
/// refuses it.
///
/// The local echo is set first so the menu and the footer update on the tap
/// rather than on the round trip; see [presenceVisibilityDisplayProvider] for
/// why that echo exists at all. A rejected change must not leave it asserting
/// a visibility the server never applied - a stale "appear offline" is still
/// hidden, but a stale "online" is exactly the lie this feature exists to
/// prevent.
///
/// [guard] is the caller's own [GuardedActionState.guard], so the failure
/// lands in whichever surface is already set up to render it as
/// [AppErrorState] rather than this having an opinion of its own.
Future<bool> applyPresenceVisibility(
  WidgetRef ref,
  api.PresenceVisibility visibility, {
  required Guard guard,
}) async {
  final notifier = ref.read(presenceVisibilityDisplayProvider.notifier);
  final previous = notifier.state;
  notifier.state = visibility;
  final ok = await guard(
    whatFailed: 'update your status',
    action: () => ref.read(apiProvider).setPresenceVisibility(visibility),
  );
  if (!ok) notifier.state = previous;
  return ok;
}

/// The rail footer's avatar, as a tap target that opens the status menu
/// upward off the bottom bar on a pointer layout, or as a bottom sheet under
/// `kCompactWidth` - the same anchored-vs-sheet split `member_profile.dart`
/// uses, per `docs/design/desktop-vs-mobile.md`: an anchored surface under a
/// thumb is a review defect.
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

  /// Finger-down feedback, the same shape [AppIconButton] uses: nothing else
  /// here draws a hover fill for a tap to interrupt.
  bool _pressed = false;

  /// Opens the sheet on a compact width. A fresh [_PresenceMenuItems] owns
  /// this presentation's own guarded-action state, the same reason
  /// `member_profile.dart` gives `MemberProfileBody` a fresh instance per
  /// presentation: this content lives in the sheet route's own subtree, not
  /// this button's, so a refusal here cannot be shown by setting state on the
  /// button.
  Future<void> _openSheet(BuildContext context) {
    return showAppSheet<void>(
      context,
      bare: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: _PresenceMenuItems(
          onDone: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < kCompactWidth) {
      unawaited(_openSheet(context));
    } else {
      _controller.toggle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        // Positioned so the follower sizes to its content: an overlay child
        // is otherwise laid out against the whole screen, which a Column
        // fills. Only ever shown on a pointer layout; see [_open].
        overlayChildBuilder: (context) => Positioned(
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
              // Escape closes it and Tab reaches every item once open.
              child: ContextMenuKeyboardScope(
                onDismiss: _controller.hide,
                child: _PresenceMenuItems(onDone: _controller.hide),
              ),
            ),
          ),
        ),
        // A 28pt avatar is well under the touch minimum, so the tap area is
        // grown around it rather than the glyph being grown to match.
        child: Semantics(
          button: true,
          label: 'Change your status',
          onTap: () => _open(context),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: () {
              AppHaptics.selection();
              _open(context);
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: AppSizes.rowTouch,
                minHeight: AppSizes.rowTouch,
              ),
              child: Center(
                child: AnimatedScale(
                  scale: _pressed ? AppMotion.pressScale : 1,
                  duration: AppMotion.reduced(context, AppMotion.fast),
                  curve: AppMotion.entrance,
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
      ),
    );
  }
}

/// The status choices themselves: an [AppMenu] anchored beside the avatar on
/// a pointer layout, or a bare column filling a bottom sheet on a compact
/// one - [AppSheetMenu] picks between the two off the live window width, so
/// this same widget is what both [_PresenceMenuButtonState] presentations
/// wrap.
///
/// A fresh instance per presentation, so [GuardedActionState.actionError]
/// belongs to whichever surface is open rather than to the button that
/// opened it.
class _PresenceMenuItems extends ConsumerStatefulWidget {
  const _PresenceMenuItems({required this.onDone});

  /// Closes whichever surface this is presented in: the overlay's
  /// `OverlayPortalController.hide` on a pointer layout, `Navigator.pop` in
  /// the sheet.
  final VoidCallback onDone;

  @override
  ConsumerState<_PresenceMenuItems> createState() => _PresenceMenuItemsState();
}

class _PresenceMenuItemsState extends ConsumerState<_PresenceMenuItems>
    with GuardedActionState<_PresenceMenuItems> {
  /// Applies [visibility] and closes the menu once the server has agreed to
  /// it. A refusal leaves the menu open with [actionError] rendered inline,
  /// rather than closing over a change that never happened.
  Future<void> _select(api.PresenceVisibility visibility) async {
    final ok = await applyPresenceVisibility(ref, visibility, guard: guard);
    if (ok && mounted) widget.onDone();
  }

  /// Opens the free-text status editor (backlog item 128), leaving this menu
  /// closed behind it the same way [SpaceMenuButton] hides itself before
  /// opening the create-channel sheet: this widget's own `context` still
  /// reaches the enclosing `Navigator` once closed, since closing either
  /// presentation unmounts this subtree rather than the tree above it.
  void _openStatusEditor(BuildContext context, String current) {
    widget.onDone();
    unawaited(showStatusEditorSheet(context, current));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final selected = ref.watch(presenceVisibilityDisplayProvider);
    final currentStatus = ref.watch(meProvider).valueOrNull?.statusText ?? '';
    // Rule 2 of desktop-vs-mobile.md: status is a dropdown everywhere there is room for one, only compact still needs the sheet.
    final desktop = MediaQuery.sizeOf(context).width >= kCompactWidth;

    // [selected] is null until a choice is made in this session, and then no
    // item is marked current: ticking one would assert a stored value this
    // client has no way to read back.
    return AppSheetMenu(
      width: 220,
      children: [
        if (desktop)
          PresenceStatusField(current: currentStatus, onDone: widget.onDone)
        else
          AppMenuItem(
            label: 'Set a status',
            leading: AppIcons.smile,
            onTap: () => _openStatusEditor(context, currentStatus),
          ),
        const AppMenuDivider(),
        const AppMenuLabel('Status'),
        for (final (visibility, label, presence) in presenceOptions)
          AppMenuItem(
            label: label,
            selected: visibility == selected,
            // surfaceRaised, not the default, because the dnd notch and the
            // appear-offline slash punch their mark here.
            trailing: AppStatusDot(
              status: presence,
              backgroundColor: tokens.surfaceRaised,
            ),
            onTap: () => unawaited(_select(visibility)),
          ),
        if (actionError != null)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.s8),
            child: AppErrorState(
              message: actionError!,
              onDismiss: clearActionError,
            ),
          ),
      ],
    );
  }
}
