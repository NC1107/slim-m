// SPDX-License-Identifier: Apache-2.0
/// Settings' avatar section: a preview of the caller's own picture plus
/// upload and remove actions, following the same pick-bytes-then-upload
/// shape the composer's attachment picker already uses.
library;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../api_failure.dart';
import '../providers/providers.dart';
import 'avatar_crop_sheet.dart';
import 'settings_section_header.dart';
import 'user_avatar.dart';

class AvatarSettingsSection extends ConsumerStatefulWidget {
  const AvatarSettingsSection({super.key});

  @override
  ConsumerState<AvatarSettingsSection> createState() =>
      _AvatarSettingsSectionState();
}

class _AvatarSettingsSectionState extends ConsumerState<AvatarSettingsSection> {
  bool _busy = false;

  Future<void> _upload() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(type: FileType.image);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the file picker.')),
      );
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
    try {
      await ref.read(apiProvider).uploadAvatar(bytes);
      if (context.mounted) ref.invalidate(meProvider);
    } on api.ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeApiFailure('upload the avatar', e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).deleteAvatar();
      if (context.mounted) ref.invalidate(meProvider);
    } on api.ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeApiFailure('remove the avatar', e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider).valueOrNull;
    final hasAvatar = me?.avatarUpdatedAt != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsSectionHeader('Avatar'),
        // Bottom padding, not just horizontal: the row was the only section
        // content with none, so the disc sat flush on the divider below it.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s16,
            0,
            AppSpacing.s16,
            AppSpacing.s16,
          ),
          child: Row(
            children: [
              UserAvatar(
                userId: me?.id,
                avatarUpdatedAt: me?.avatarUpdatedAt,
                name: me?.displayName ?? '',
                size: 56,
              ),
              const SizedBox(width: AppSpacing.s16),
              if (_busy)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Wrap(
                  spacing: AppSpacing.s8,
                  children: [
                    TextButton(
                      onPressed: me == null ? null : _upload,
                      child: const Text('Upload photo'),
                    ),
                    if (hasAvatar)
                      TextButton(
                        onPressed: _remove,
                        child: const Text('Remove'),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}
