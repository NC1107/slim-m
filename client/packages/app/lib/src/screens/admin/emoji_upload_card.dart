// SPDX-License-Identifier: Apache-2.0
/// Adding one custom emoji: a name, an image, and a preview of the name the
/// server will actually store.
///
/// The preview is the point. The server normalises a name to lowercase a-z,
/// 0-9 and underscore, and an uploader who types "Party Parrot" should read
/// `:party_parrot:` on screen before pressing anything, not discover it in
/// the list afterwards. What is previewed is what is sent, so the two cannot
/// drift; see `emoji_name.dart`.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../../api_failure.dart';
import '../../providers/admin_providers.dart';
import '../../providers/providers.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/image_decode.dart';
import 'emoji_name.dart';

/// Picks an image and returns its bytes, or null if nothing was chosen.
typedef EmojiImagePicker = Future<List<int>?> Function();

/// The picker this card uses, injectable because `file_picker` has no
/// platform implementation under test: without a seam, a widget test can tap
/// the button and never get past it, which is exactly why the avatar
/// section's upload path is asserted only up to "nothing was uploaded".
final emojiImagePickerProvider = Provider<EmojiImagePicker>(
  (ref) => _pickImageBytes,
);

/// The extensions the server actually stores an emoji as: the inline subset
/// of `media::ALLOWED_TYPES` in `crates/slimm-server/src/media.rs`.
const acceptedEmojiExtensions = ['png', 'jpg', 'jpeg', 'gif', 'webp'];

/// `FileType.custom`, not `FileType.image`: on iOS the latter opens only the
/// Photos-backed `PHPickerViewController`, which cannot see a file that
/// arrived by download, Files, or a messaging app rather than the camera
/// roll. An extension filter opens `UIDocumentPickerViewController` instead,
/// which can reach all of those (and is the Android SAF browser there too).
Future<List<int>?> _pickImageBytes() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: acceptedEmojiExtensions,
  );
  final files = result?.files ?? const <PlatformFile>[];
  if (files.isEmpty) return null;
  // readAsBytes streams from disk since eager loading OOMs on a large pick.
  return files.first.readAsBytes();
}

class EmojiUploadCard extends ConsumerStatefulWidget {
  const EmojiUploadCard({super.key});

  @override
  ConsumerState<EmojiUploadCard> createState() => _EmojiUploadCardState();
}

class _EmojiUploadCardState extends ConsumerState<EmojiUploadCard> {
  final _name = TextEditingController();
  List<int>? _bytes;
  bool _submitting = false;
  String? _refusal;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final List<int>? bytes;
    try {
      bytes = await ref.read(emojiImagePickerProvider)();
    } catch (e) {
      if (!mounted) return;
      showAppSnackbar(context, 'Could not open the file picker.');
      return;
    }
    if (bytes == null || !mounted) return;
    setState(() {
      _bytes = bytes;
      _refusal = null;
    });
  }

  Future<void> _submit() async {
    final name = normalizeEmojiName(_name.text);
    final bytes = _bytes;
    if (bytes == null || !isUsableEmojiName(name)) return;

    setState(() {
      _submitting = true;
      _refusal = null;
    });
    try {
      await ref.read(apiProvider).uploadCustomEmoji(bytes, name: name);
      if (context.mounted) ref.invalidate(customEmojiProvider);
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _bytes = null;
        _name.clear();
      });
    } on api.ConflictException catch (e) {
      // 409 is either the name or the deployment's cap, and only the server's
      // own reason separates them, so it is shown rather than paraphrased.
      _refuse('${emojiShortcode(name)} was refused: ${e.message}.');
    } on api.ApiException catch (e) {
      // Not the bare shortcode: its own trailing colon collides with the one some failure sentences end in.
      _refuse(describeApiFailure('add the ${emojiShortcode(name)} emoji', e));
    }
  }

  void _refuse(String message) {
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _refusal = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final normalized = normalizeEmojiName(_name.text);
    final usable = isUsableEmojiName(normalized);
    // Refusing a name the loaded list already holds saves a round trip whose
    // only possible answer is 409; the catch below still covers the race.
    final existing = ref.watch(customEmojiProvider).valueOrNull;
    final taken =
        usable && (existing?.any((e) => e.name == normalized) ?? false);
    final refusal = _refusal;

    return AppCard(
      title: 'New emoji',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (refusal != null) ...[
            AppCallout(tone: AppCalloutTone.warn, child: Text(refusal)),
            const SizedBox(height: AppSpacing.s12),
          ],
          AppInput(
            controller: _name,
            placeholder: 'Name',
            semanticLabel: 'Emoji name',
            errorText: taken ? 'Already taken.' : null,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.s8),
          _NamePreview(typed: _name.text, normalized: normalized, taken: taken),
          const SizedBox(height: AppSpacing.s12),
          if (_bytes case final bytes?) ...[
            _EmojiImagePreview(
              bytes: bytes,
              onClear: () => setState(() => _bytes = null),
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
          AppButton(
            label: _bytes == null ? 'Choose image' : 'Choose a different image',
            icon: _bytes == null ? AppIcons.add : AppIcons.image,
            full: true,
            disabled: _submitting,
            onPressed: _pick,
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            'PNG, JPEG, GIF or WEBP.',
            style: AppText.caption.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.s12),
          AppButton(
            label: _submitting ? 'Adding...' : 'Add emoji',
            icon: AppIcons.smile,
            variant: AppButtonVariant.primary,
            full: true,
            disabled: _submitting || _bytes == null || !usable || taken,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

/// What the server will store, shown while typing.
///
/// Four states rather than one: "nothing usable", "too long" and "already
/// taken" are refusals the uploader can act on, and a blank line would leave
/// them guessing why the button is disabled. Taken renders nothing rather
/// than its own sentence, because [AppInput]'s error slot already names the
/// problem right above this line; repeating it here previously left "Already
/// taken." sitting directly beside "Will be added as :name:", one line
/// promising the upload would succeed and the other saying it could not.
class _NamePreview extends StatelessWidget {
  const _NamePreview({
    required this.typed,
    required this.normalized,
    required this.taken,
  });

  final String typed;
  final String normalized;
  final bool taken;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    if (taken) return const SizedBox.shrink();

    if (typed.trim().isEmpty) {
      return Text(
        'Members type it between colons.',
        style: AppText.caption.copyWith(color: tokens.textSecondary),
      );
    }
    if (normalized.isEmpty) {
      return Text(
        'Nothing usable there: letters, numbers and underscores only.',
        style: AppText.caption.copyWith(color: tokens.dangerText),
      );
    }
    if (normalized.length > maxEmojiNameLength) {
      return Text(
        'Too long: $maxEmojiNameLength characters at most, '
        'after spaces become underscores.',
        style: AppText.caption.copyWith(color: tokens.dangerText),
      );
    }
    return Row(
      children: [
        Text(
          'Will be added as ',
          style: AppText.caption.copyWith(color: tokens.textSecondary),
        ),
        Flexible(
          child: Text(
            emojiShortcode(normalized),
            overflow: TextOverflow.ellipsis,
            style: AppText.caption.copyWith(
              color: tokens.textPrimary,
              fontFamily: AppFonts.mono,
            ),
          ),
        ),
      ],
    );
  }
}

/// The picked image, at the two sizes the app actually draws an emoji at
/// (inline in a message body, and in this same admin list once uploaded), so
/// an uploader sees the picture rather than a checkmark standing in for it.
class _EmojiImagePreview extends StatelessWidget {
  const _EmojiImagePreview({required this.bytes, required this.onClear});

  final List<int> bytes;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final data = Uint8List.fromList(bytes);

    return Row(
      children: [
        _swatch(context, data, 20, tokens),
        const SizedBox(width: AppSpacing.s12),
        _swatch(context, data, 32, tokens),
        const Spacer(),
        AppIconButton(
          icon: AppIcons.dismiss,
          semanticLabel: 'Remove the chosen image',
          onPressed: onClear,
        ),
      ],
    );
  }

  Widget _swatch(
    BuildContext context,
    Uint8List data,
    double size,
    AppTokens tokens,
  ) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      border: Border.all(color: tokens.borderSubtle),
      borderRadius: BorderRadius.circular(AppRadii.control),
    ),
    // Never decodes past the pixels this swatch is ever drawn at.
    child: Image.memory(
      data,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      cacheWidth: decodeEdge(context, size),
      cacheHeight: decodeEdge(context, size),
    ),
  );
}
