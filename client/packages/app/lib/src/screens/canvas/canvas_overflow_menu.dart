// SPDX-License-Identifier: Apache-2.0
/// The canvas bar's overflow: always present for "Paste image", since
/// placing an image needs only the USE_CANVAS bit drawing already does, with
/// "Clear canvas" appearing inside it only for MANAGE_CANVAS.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../../widgets/confirm_dialog.dart';

/// The bar's own overflow trigger and the confirm dialog behind Clear.
///
/// Clear stays behind a menu item rather than a bare button even when it is
/// the only reason a manager opens this: the extra tap is deliberate
/// friction on the one destructive control here, matching
/// `manage_channel_sheet.dart`'s own danger-zone separation.
class CanvasOverflowMenu extends StatefulWidget {
  const CanvasOverflowMenu({
    super.key,
    required this.onPasteImage,
    required this.canManage,
    required this.objectCount,
    required this.onClear,
  });

  final VoidCallback onPasteImage;
  final bool canManage;
  final ValueListenable<int> objectCount;
  final Future<void> Function() onClear;

  @override
  State<CanvasOverflowMenu> createState() => _CanvasOverflowMenuState();
}

class _CanvasOverflowMenuState extends State<CanvasOverflowMenu> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

  void _paste() {
    _controller.hide();
    widget.onPasteImage();
  }

  Future<void> _requestClear() async {
    _controller.hide();
    final count = widget.objectCount.value;
    final confirmed = await confirmDangerousAction(
      context,
      title: 'Clear this canvas?',
      message: count == 1
          ? 'This removes the one object on the canvas for everyone in '
                'this channel. This cannot be undone.'
          : 'This removes all $count objects from the canvas for everyone '
                'in this channel. This cannot be undone.',
      confirmLabel: 'Clear canvas',
      cancelLabel: 'Keep canvas',
    );
    if (confirmed) await widget.onClear();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _controller,
        overlayChildBuilder: (_) => _buildMenu(),
        child: AppIconButton(
          icon: AppIcons.moreVertical,
          semanticLabel: 'More canvas actions',
          onPressed: _controller.toggle,
        ),
      ),
    );
  }

  Widget _buildMenu() {
    return Positioned(
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
                label: 'Paste image',
                leading: AppIcons.clipboardPaste,
                onTap: _paste,
              ),
              if (widget.canManage) ...[
                const AppMenuDivider(),
                AppMenuItem(
                  label: 'Clear canvas',
                  leading: AppIcons.delete,
                  tone: AppMenuItemTone.danger,
                  onTap: () => unawaited(_requestClear()),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
