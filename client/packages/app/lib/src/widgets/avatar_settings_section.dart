// SPDX-License-Identifier: Apache-2.0
/// Settings' avatar section: a centred preview of the caller's own picture
/// with a camera badge that reads as "tap to change", plus a way to remove
/// an existing one.
///
/// The badge opens the same two-source choice the composer's attach action
/// already offers, rather than one picker directly: a Photos-only pick
/// cannot reach a picture that arrived by download or AirDrop. See
/// `attachment_picker.dart`.
library;

import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' show SlimmApiUsers;
import 'package:slimm_design_system/design_system.dart';

import '../providers/providers.dart';
import 'attachment_picker.dart';
import 'avatar_crop_sheet.dart';
import 'run_guarded.dart';
import 'settings_section_header.dart';
import 'user_avatar.dart';

/// Large enough on its own to clear the 44pt touch minimum, so the badge
/// never needs a separately expanded hit target the way a small icon button
/// would.
const double _avatarSize = 72;
const double _badgeSize = 28;

class AvatarSettingsSection extends ConsumerStatefulWidget {
  const AvatarSettingsSection({super.key});

  @override
  ConsumerState<AvatarSettingsSection> createState() =>
      _AvatarSettingsSectionState();
}

class _AvatarSettingsSectionState extends ConsumerState<AvatarSettingsSection>
    with GuardedActionState<AvatarSettingsSection> {
  bool _busy = false;

  Future<AttachmentSource?> _pickSource() {
    return showAppSheet<AttachmentSource>(
      context,
      builder: (sheetContext) {
        final tokens = Theme.of(sheetContext).extension<AppTokens>()!;
        const options = [
          (AppIcons.image, 'Photo library', AttachmentSource.photoLibrary),
          (AppIcons.attachFile, 'Browse files', AttachmentSource.fileBrowser),
        ];
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s12,
              0,
              AppSpacing.s12,
              AppSpacing.s12,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final (icon, label, source) in options)
                  AppListRow(
                    label: label,
                    leading: Icon(
                      icon,
                      size: AppSizes.icon16,
                      color: tokens.textSecondary,
                    ),
                    onTap: () => Navigator.of(sheetContext).pop(source),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Fires the same tick every other tappable in this system does, since a
  /// plain [InkWell] carries none of that on its own.
  void _onTapChange() {
    AppHaptics.selection();
    unawaited(_changePicture());
  }

  Future<void> _changePicture() async {
    final source = await _pickSource();
    if (source == null || !mounted) return;

    // Cleared up front, same precedent as composer.dart's own _pickAttachment: a retry must not keep showing an earlier failure.
    clearActionError();
    final FilePickerResult? result;
    try {
      result = await ref.read(attachmentPickerProvider(source))();
    } catch (e) {
      setActionError('Could not open the file picker.');
      return;
    }
    final files = result?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;
    // readAsBytes streams from disk; file_picker 12 deprecated withData and
    // PlatformFile.bytes because eager loading OOMs on a large pick.
    final picked = await files.first.readAsBytes();
    if (!mounted) return;

    // Cropped before upload, not after: the server caps an avatar at 2 MB and
    // a phone photo is routinely past that, so the raw pick simply failed.
    final bytes = await showAvatarCropSheet(context, picked);
    if (bytes == null || !mounted) return;

    setState(() => _busy = true);
    final ok = await guard(
      whatFailed: 'upload the avatar',
      action: () => ref.read(apiProvider).uploadAvatar(bytes),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) ref.invalidate(meProvider);
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    final ok = await guard(
      whatFailed: 'remove the avatar',
      action: () => ref.read(apiProvider).deleteAvatar(),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) ref.invalidate(meProvider);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final me = ref.watch(meProvider).valueOrNull;
    final hasAvatar = me?.avatarUpdatedAt != null;
    final enabled = me != null && !_busy;

    return SettingsSectionCard(
      title: 'Avatar',
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.s8),
          child: Column(
            children: [
              Semantics(
                button: true,
                enabled: enabled,
                label: 'Change profile picture',
                child: AppFocusRing(
                  radius: _avatarSize / 2,
                  builder: (context, onFocusChange) => InkWell(
                    onTap: enabled ? _onTapChange : null,
                    // AppFocusRing replaces this overlay; see its own doc comment.
                    focusColor: Colors.transparent,
                    onFocusChange: onFocusChange,
                    customBorder: const CircleBorder(),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ExcludeSemantics(
                          child: UserAvatar(
                            userId: me?.id,
                            avatarUpdatedAt: me?.avatarUpdatedAt,
                            name: me?.displayName ?? '',
                            size: _avatarSize,
                          ),
                        ),
                        if (_busy)
                          Positioned.fill(
                            child: ExcludeSemantics(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: tokens.surfaceBase.withValues(
                                    alpha: 0.6,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: ExcludeSemantics(
                            child: Container(
                              width: _badgeSize,
                              height: _badgeSize,
                              decoration: BoxDecoration(
                                color: tokens.accentFill,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: tokens.surfaceBase,
                                  width: 2,
                                ),
                              ),
                              child: Icon(
                                AppIcons.avatarCamera,
                                size: AppSizes.icon16,
                                color: tokens.accentOn,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (hasAvatar) ...[
                const SizedBox(height: AppSpacing.s8),
                AppButton(
                  label: 'Remove',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.sm,
                  onPressed: enabled ? _remove : null,
                ),
              ],
              if (actionError != null) ...[
                const SizedBox(height: AppSpacing.s8),
                AppErrorState(
                  message: actionError!,
                  onDismiss: clearActionError,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
