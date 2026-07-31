// SPDX-License-Identifier: Apache-2.0
/// The overflow behind "Clear canvas": one menu item, gated on MANAGE_CANVAS
/// by the caller, so a control the operator never granted never renders.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:slimm_design_system/design_system.dart';

import '../../widgets/confirm_dialog.dart';

/// The bar's own overflow trigger and the confirm dialog behind it.
///
/// A single item still goes behind a menu rather than a bare button: the
/// extra tap is deliberate friction on the one destructive control here,
/// matching `manage_channel_sheet.dart`'s own danger-zone separation.
class CanvasClearMenu extends StatefulWidget {
  const CanvasClearMenu({
    super.key,
    required this.objectCount,
    required this.onClear,
  });

  final ValueListenable<int> objectCount;
  final Future<void> Function() onClear;

  @override
  State<CanvasClearMenu> createState() => _CanvasClearMenuState();
}

class _CanvasClearMenuState extends State<CanvasClearMenu> {
  final _controller = OverlayPortalController();
  final _link = LayerLink();

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
                label: 'Clear canvas',
                leading: AppIcons.delete,
                tone: AppMenuItemTone.danger,
                onTap: () => unawaited(_requestClear()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
