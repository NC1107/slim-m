// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The menu the profile picture opens: take, choose, browse, remove.
///
/// One `showAppSheet` call, so it is a bottom sheet with handle and 44dp rows
/// under `kCompactWidth` and the floating menu above it (rule 3 of
/// `docs/design/desktop-vs-mobile.md`).
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_design_system/design_system.dart';

enum AvatarPhotoAction { take, choose, browse, remove }

/// Captures one photo with the camera, or null when the user backs out.
typedef AvatarCameraCapture = Future<Uint8List?> Function();

/// Null where this build cannot reach a camera, which hides "Take photo".
///
/// No capture plugin is wired yet, so every platform answers null; a build
/// that gains one overrides this rather than editing the menu.
final avatarCameraCaptureProvider = Provider<AvatarCameraCapture?>(
  (ref) => null,
);

Future<AvatarPhotoAction?> showAvatarPhotoMenu(
  BuildContext context, {
  required bool canTake,
  required bool canRemove,
}) {
  return showAppSheet<AvatarPhotoAction>(
    context,
    bare: true,
    builder: (sheetContext) {
      void pick(AvatarPhotoAction action) =>
          Navigator.of(sheetContext).pop(action);
      return AppSheetMenu(
        children: [
          if (canTake)
            AppMenuItem(
              label: 'Take photo',
              leading: AppIcons.avatarCamera,
              onTap: () => pick(AvatarPhotoAction.take),
            ),
          AppMenuItem(
            label: 'Choose photo',
            leading: AppIcons.image,
            onTap: () => pick(AvatarPhotoAction.choose),
          ),
          AppMenuItem(
            label: 'Browse files',
            leading: AppIcons.attachFile,
            onTap: () => pick(AvatarPhotoAction.browse),
          ),
          if (canRemove)
            AppMenuItem(
              label: 'Remove photo',
              leading: AppIcons.delete,
              tone: AppMenuItemTone.danger,
              onTap: () => pick(AvatarPhotoAction.remove),
            ),
        ],
      );
    },
  );
}
