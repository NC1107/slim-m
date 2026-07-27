// SPDX-License-Identifier: Apache-2.0
/// Shared fixtures for the two suites that pump a [Composer]: its send paths
/// and its affordances (attach a file, insert a Space emoji).
///
/// Not a `_test.dart` file, so `flutter test` does not try to run it. It
/// exists because both suites need the same typing seam stubbed, the same
/// signed-in session, the same fake file picker and the same upload route,
/// none of which either suite is actually about.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/providers/admin_providers.dart';
import 'package:slimm_app/src/providers/emoji_catalog_provider.dart';
import 'package:slimm_app/src/providers/providers.dart';
import 'package:slimm_app/src/providers/typing_controller.dart';
import 'package:slimm_app/src/widgets/composer.dart';
import 'package:slimm_app/src/widgets/emoji_picker_grid.dart';
import 'package:slimm_design_system/design_system.dart';

/// Stands in for the real controller, which would open a websocket
/// subscription the moment the first keystroke reaches it.
class NoopTyping extends StateNotifier<Set<String>>
    implements TypingController {
  NoopTyping() : super(const {});

  @override
  void notifyTyping() {}
}

/// Records what the composer handed its `onSend`.
class Sends {
  int count = 0;
  List<String> ids = const [];

  Future<void> call(List<String> attachmentIds) async {
    count += 1;
    ids = attachmentIds;
  }
}

/// Answers the picker without a platform channel. `FilePicker.pickFiles`
/// delegates to this instance, and extending (never implementing) the
/// interface is what satisfies its own token check.
class FakePicker extends FilePickerPlatform {
  FakePicker(this.file, {this.failure});

  /// Null stands for a cancelled pick.
  final PlatformFile? file;

  /// Non-null makes the pick throw this instead of answering, which is what a
  /// missing portal or a refused permission does on a real device. The
  /// composer catches that separately from a cancel, so it needs its own case.
  final Object? failure;

  int calls = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
    bool cancelUploadOnWindowBlur = true,
    AndroidSAFOptions? androidSafOptions,
  }) async {
    calls += 1;
    if (failure != null) throw failure!;
    return file == null ? null : FilePickerResult([file!]);
  }
}

/// A pick that resolves, carrying its own bytes so `readAsBytes` never
/// touches the filesystem.
PlatformFile pickedFile() => PlatformFile(
  name: 'holiday.png',
  size: 4,
  bytes: Uint8List.fromList([1, 2, 3, 4]),
);

/// Installs a fake picker for one test and puts the real one back after, so a
/// later test in the same process is not left with this one's fake.
FakePicker usePicker(PlatformFile? file, {Object? failure}) {
  final previous = FilePickerPlatform.instance;
  final picker = FakePicker(file, failure: failure);
  FilePickerPlatform.instance = picker;
  addTearDown(() => FilePickerPlatform.instance = previous);
  return picker;
}

/// Enough of a session for the upload to be attempted at all: an unsigned-in
/// client refuses it before the request is ever built.
const _tokens = api.TokenPair(
  userId: 'self',
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: 0,
);

/// A 1x1 transparent PNG: real bytes, so a custom emoji tile decodes rather
/// than throwing.
final _png = Uint8List.fromList(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8'
    'z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  ),
);

api.CustomEmoji custom(String name) =>
    api.CustomEmoji(id: 'e-$name', name: name, uploaderId: 'u1', createdAt: 1);

/// An api whose only live route is the attachment upload the composer makes.
api.SlimmApi _uploadingApi(Ref ref) => api.SlimmApi(
  baseUrl: Uri.parse('http://localhost:8080'),
  session: ref.watch(sessionProvider),
  httpClient: MockClient((request) async {
    if (request.method == 'POST' && request.url.path == '/attachments') {
      return http.Response(
        jsonEncode({
          'id': 'a1',
          'filename': 'holiday.png',
          'content_type': 'image/png',
          'size': 4,
        }),
        201,
        headers: {'content-type': 'application/json'},
      );
    }
    return http.Response('{}', 404, headers: {'content-type': 'text/plain'});
  }),
);

/// [customEmoji] null leaves the list provider alone, which is the state a
/// suite that has nothing to do with emoji sees: an unfetchable list.
Widget composerHarness({
  required TextEditingController controller,
  required Sends sends,
  required TargetPlatform platform,
  List<api.CustomEmoji>? customEmoji,
}) {
  return ProviderScope(
    overrides: [
      typingControllerProvider.overrideWith((ref, channelId) => NoopTyping()),
      sessionProvider.overrideWithValue(api.SessionStore(tokens: _tokens)),
      apiProvider.overrideWith(_uploadingApi),
      if (customEmoji != null)
        customEmojiProvider.overrideWith((ref) => customEmoji),
      customEmojiImageProvider.overrideWith((ref, id) => _png),
    ],
    child: MaterialApp(
      theme: buildTheme(
        Brightness.light,
        AppTokens.light,
      ).copyWith(platform: platform),
      home: Scaffold(
        body: Column(
          children: [
            const Spacer(),
            Composer(
              controller: controller,
              channelId: 'c1',
              channelName: 'general',
              onSend: sends.call,
            ),
          ],
        ),
      ),
    ),
  );
}

Finder get sendButton => find.ancestor(
  of: find.byIcon(AppIcons.send),
  matching: find.byType(AppIconButton),
);

Finder get attachButton => find.byWidgetPredicate(
  (w) => w is AppIconButton && w.semanticLabel == 'Attach a file',
);

Finder get emojiButton => find.byWidgetPredicate(
  (w) => w is AppIconButton && w.semanticLabel == 'Insert emoji',
);

bool fieldHasFocus(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus;

List<String> gridTokens(WidgetTester tester) => tester
    .widget<EmojiGrid>(find.byType(EmojiGrid))
    .emoji
    .map((e) => e.token)
    .toList();
