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

import '../providers/providers.dart';
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
      result = await FilePicker.pickFiles(withData: true, type: FileType.image);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the file picker. $e')));
      return;
    }
    final files = result?.files ?? const <PlatformFile>[];
    if (files.isEmpty) return;
    final bytes = files.first.bytes;
    if (bytes == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).uploadAvatar(bytes);
      if (context.mounted) ref.invalidate(meProvider);
    } on api.ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not upload the avatar. ${e.message}')));
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
          SnackBar(content: Text('Could not remove the avatar. ${e.message}')));
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
        const SettingsSectionHeader(
          'Avatar',
          description: 'Shown next to your name to other members.',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s16),
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
