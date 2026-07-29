// SPDX-License-Identifier: Apache-2.0
/// The emoji picker's entry points.
///
/// Two of them reach the full catalog, native and custom, for a reaction: a
/// floating surface opened from the add-reaction control on a message hover,
/// and a bottom sheet where there is no pointer to hover with. Both wrap the
/// one [EmojiPickerPanel], re-exported here so a caller needs this import
/// only.
///
/// The third, [showSpaceEmojiSheet], offers the Space's own emoji and nothing
/// else. It is the composer's, and the asymmetry is deliberate: a composer has
/// the phone's keyboard behind it, which already carries every native emoji
/// and does it better, while a reaction has no keyboard behind it at all.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' show CustomEmoji;
import 'package:slimm_design_system/design_system.dart';

import '../providers/admin_providers.dart';
import '../providers/recent_emoji.dart';
import 'emoji_catalog.dart';
import 'emoji_picker_grid.dart';
import 'emoji_picker_panel.dart';
import 'hover_reveal.dart';

export 'emoji_picker_panel.dart' show EmojiPickerPanel;

/// The horizontal breathing room a sheet leaves on each side, so the panel's
/// own border never sits flush against the screen edge.
const double _sheetInset = AppSpacing.s8;

/// The add-reaction glyph, anchored so its picker opens beneath it and
/// closes on an outside tap, an escape, or a pick. Mirrors the Space
/// menu's own `CompositedTransformTarget`/`OverlayPortal` pairing in
/// `channel_rail_frame.dart`.
class EmojiPickerButton extends StatefulWidget {
  const EmojiPickerButton({super.key, required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  State<EmojiPickerButton> createState() => _EmojiPickerButtonState();
}

class _EmojiPickerButtonState extends State<EmojiPickerButton> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  /// Keeps the row that reveals this button on hover from unmounting it while
  /// the panel is open, since reaching the panel takes the pointer off the row.
  void _setOpen(bool open) {
    HoverRevealScope.maybeOf(context)?.pin(open);
    open ? _controller.show() : _controller.hide();
  }

  void _select(String emoji) {
    _setOpen(false);
    widget.onSelect(emoji);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        // Positioned so the follower sizes to its content: an overlay child is
        // otherwise laid out against the whole screen, which a Column fills.
        overlayChildBuilder: (context) => Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 4),
            child: TapRegion(
              onTapOutside: (_) => _setOpen(false),
              child: EmojiPickerPanel(
                onSelect: _select,
                onClose: () => _setOpen(false),
              ),
            ),
          ),
        ),
        child: AppIconButton(
          icon: AppIcons.smile,
          semanticLabel: 'Add a reaction',
          iconSize: AppSizes.icon16,
          onPressed: () => _setOpen(!_controller.isShowing),
        ),
      ),
    );
  }
}

/// Opens the picker as a bottom sheet: the touch-reachable counterpart to
/// [EmojiPickerButton]'s hover-anchored overlay, wrapping the same panel
/// rather than a second implementation of it.
///
/// [onSelect] runs after the sheet has popped, so a caller that moves focus
/// (the composer re-focusing its field) is not fighting the closing route.
Future<void> showEmojiPickerSheet(
  BuildContext context, {
  required ValueChanged<String> onSelect,
}) {
  return _sheet(
    context,
    // The width the sheet has, not the desktop popup's 320: clamping there
    // left a third of a phone unused. EmojiGrid keeps a wide one's cells sane.
    (context, width) => EmojiPickerPanel(
      autofocusSearch: false,
      width: width,
      onSelect: (emoji) {
        Navigator.of(context).pop();
        onSelect(emoji);
      },
      onClose: () => Navigator.of(context).pop(),
    ),
  );
}

/// Opens the composer's emoji entry point: the Space's own emoji, and only
/// those. A Space with none says so rather than opening an empty grid.
///
/// [onSelect] runs after the sheet has popped, matching
/// [showEmojiPickerSheet], so the composer's re-focus is not fighting the
/// closing route.
Future<void> showSpaceEmojiSheet(
  BuildContext context, {
  required ValueChanged<String> onSelect,
}) {
  return _sheet(
    context,
    (context, width) => SizedBox(
      width: width,
      child: _SpaceEmojiSheet(
        onSelect: (emoji) {
          Navigator.of(context).pop();
          onSelect(emoji);
        },
      ),
    ),
  );
}

/// The shape both sheets share: keyboard-inset aware, safe-area aware, and
/// measured so its child is handed the width it really has.
Future<void> _sheet(
  BuildContext context,
  Widget Function(BuildContext context, double width) build,
) {
  return showAppSheet<void>(
    context,
    maxWidth: 520,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        left: _sheetInset,
        right: _sheetInset,
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      // Inside the keyboard inset, so the two cancel out: the route already
      // removes the top padding, which is why this matches its sibling sheet.
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) =>
                  build(context, constraints.maxWidth),
            ),
          ],
        ),
      ),
    ),
  );
}

/// The Space's own emoji as a grid, with a plain sentence in place of every
/// state that has nothing to show: still loading, unreachable, or genuinely
/// none uploaded yet.
class _SpaceEmojiSheet extends ConsumerWidget {
  const _SpaceEmojiSheet({required this.onSelect});

  final ValueChanged<String> onSelect;

  /// A ceiling, not a height: a Space with four emoji gets one row.
  static const double _maxGridHeight = 260;

  void _pick(WidgetRef ref, PickerEmoji emoji) {
    ref.read(recentEmojiProvider.notifier).use(emoji.token);
    onSelect(emoji.token);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final custom = ref.watch(customEmojiProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s8),
      child: switch (custom) {
        AsyncError() => const _SheetMessage(
          'Could not load the emoji for this Space.',
        ),
        AsyncData(value: final List<CustomEmoji> emoji) when emoji.isEmpty =>
          const _SheetMessage(
            'This Space has no custom emoji yet. Native emoji are on your '
            'keyboard.',
          ),
        AsyncData(value: final List<CustomEmoji> emoji) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s12,
                0,
                AppSpacing.s12,
                AppSpacing.s8,
              ),
              child: Text(
                'Space emoji',
                style: AppText.label.copyWith(color: tokens.textSecondary),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: _maxGridHeight),
              child: EmojiGrid(
                shrinkWrap: true,
                emoji: [for (final e in emoji) DeploymentEmoji(e)],
                // No keyboard navigation in a sheet, so nothing is on deck.
                highlighted: -1,
                onTap: (picked) => _pick(ref, picked),
              ),
            ),
          ],
        ),
        _ => const _SheetMessage('Loading the emoji for this Space...'),
      },
    );
  }
}

/// One centered sentence, for a sheet with no grid to draw.
class _SheetMessage extends StatelessWidget {
  const _SheetMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s16,
        AppSpacing.s8,
        AppSpacing.s16,
        AppSpacing.s24,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppText.body.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}
