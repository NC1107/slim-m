// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// Renders overlays open, not resting screens: a sheet, dialog or popover
/// shows nothing on a screenshot of what is underneath it, so each of these
/// is driven open through its real `show*` entry point and rendered while
/// mounted.
///
/// Two viewports per surface (desktop, where `showAppSheet` renders a
/// centred dialog, and a phone, where it collapses to a bottom sheet), one
/// theme (dark - light is already covered broadly by `ui_snapshot_test.dart`
/// and the golden matrix). The overflow assertion runs everywhere including
/// CI; the PNGs are written only under SLIMM_UI_SNAPSHOTS=1, matching
/// `ui_snapshot_test.dart`'s own split.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_app/src/widgets/avatar_crop_sheet.dart';
import 'package:slimm_app/src/widgets/camera_source_sheet.dart';
import 'package:slimm_app/src/widgets/command_palette.dart';
import 'package:slimm_app/src/widgets/composer_extras.dart';
import 'package:slimm_app/src/widgets/confirm_dialog.dart';
import 'package:slimm_app/src/widgets/create_channel_sheet.dart';
import 'package:slimm_app/src/widgets/emoji_picker.dart';
import 'package:slimm_app/src/widgets/member_profile.dart';
import 'package:slimm_app/src/widgets/member_roles_sheet.dart';
import 'package:slimm_app/src/widgets/pinned_messages_sheet.dart';
import 'package:slimm_app/src/widgets/poll_composer_sheet.dart';
import 'package:slimm_app/src/widgets/report_dialog.dart';
import 'package:slimm_app/src/widgets/screen_source_sheet.dart';
import 'package:slimm_app/src/widgets/whats_new_sheet.dart';
import 'package:slimm_app/src/whats_new/whats_new_content.dart';
import 'package:slimm_app/src/screens/admin/overwrite_target_picker_sheets.dart';
import 'package:slimm_app/src/screens/admin/role_editor_sheet.dart';
import 'package:slimm_data/data.dart' show Channel;
import 'package:slimm_design_system/design_system.dart';
import 'package:slimm_rtc/rtc.dart' show CameraDevice, ScreenShareSource;

import 'support/mid_flight_capture.dart';
import 'ui_snapshot_support.dart';

/// A 1x1 PNG, the same fixture `avatar_crop_sheet_test.dart` uses: all the
/// sheet needs to lay itself out.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, //
  0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, //
  0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, //
  0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D, //
  0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, //
  0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

/// One row's worth of `channel_management_test.dart`'s own construction: the
/// manage sheet needs the local drift row, not the wire `api.Channel`.
final _localChannel = Channel(
  id: 'c-general',
  name: 'general',
  kind: 'text',
  createdAt: 0,
  position: 0,
  topic: 'General chat for the whole Space.',
  cursor: 0,
  lastReadSeq: 0,
  isPersonalSpace: false,
);

const _adaProfile = api.UserProfile(
  id: 'user-ada',
  username: 'ada',
  displayName: 'Ada Lovelace',
  createdAt: 0,
);

/// Two entries, the same as `camera_source_sheet_test.dart`'s own fixture:
/// enough to show the picker choosing between more than one device.
const _cameraDevices = [
  CameraDevice(id: 'cam-0', label: 'FaceTime HD Camera'),
  CameraDevice(id: 'cam-1', label: 'Logitech BRIO'),
];

const _screenSources = [
  ScreenShareSource(id: 'screen-0', name: 'Screen 1'),
  ScreenShareSource(id: 'screen-1', name: 'Screen 2'),
];

/// Every overlay under review, keyed by name; each opens itself given a
/// mounted [BuildContext] and [WidgetRef].
final _overlays = <String, FutureOr<void> Function(BuildContext, WidgetRef)>{
  'confirm-dialog': (context, ref) => confirmDangerousAction(
    context,
    title: 'Delete this account?',
    message:
        'Your devices, read state, and blocks are erased, and the username '
        'becomes available again.\n\nThis cannot be undone.',
    confirmLabel: 'Delete permanently',
    cancelLabel: 'Keep my account',
  ),
  'report-dialog': (context, ref) =>
      promptReportReason(context, subjectLabel: 'this message'),
  'create-channel-sheet': (context, ref) =>
      showCreateChannelSheet(context, initialKind: 'text'),
  'pinned-messages-sheet': (context, ref) =>
      showPinnedMessagesSheet(context, 'c-general'),
  'poll-composer-sheet': (context, ref) =>
      showPollComposerSheet(context, 'c-general'),
  'member-roles-sheet': (context, ref) =>
      showMemberRolesSheet(context, 'user-long-name'),
  'role-editor-sheet': (context, ref) => showRoleEditorSheet(context),
  'avatar-crop-sheet': (context, ref) => showAvatarCropSheet(context, _png),
  'whats-new-sheet': (context, ref) =>
      showWhatsNewSheet(context, whatsNewEntries),
  'member-profile-popover': (context, ref) => showMemberProfile(
    context,
    ref,
    profile: _adaProfile,
    status: AppPresence.online,
  ),
  'command-palette': (context, ref) => openCommandPalette(context),
  'composer-actions-sheet': (context, ref) => showComposerActionsSheet(
    context,
    onPhotoLibrary: () {},
    onBrowseFiles: () {},
    canPasteImage: Future.value(false),
    onPasteImage: () {},
    onPoll: () {},
    onCode: () {},
  ),
  'camera-source-sheet': (context, ref) =>
      showCameraDeviceSheet(context, _cameraDevices),
  'screen-source-sheet': (context, ref) =>
      showScreenSourceSheet(context, _screenSources),
  'emoji-picker-sheet': (context, ref) =>
      showEmojiPickerSheet(context, onSelect: (_) {}),
  'space-emoji-sheet': (context, ref) =>
      showSpaceEmojiSheet(context, onSelect: (_) {}),
  // The three ChannelOverwritesScreen picker sheets, spot-checked before.
  'channel-picker-sheet': (context, ref) => showAppSheet<Channel>(
    context,
    builder: (context) => ChannelPickerSheet(channels: [_localChannel]),
  ),
  'role-picker-sheet': (context, ref) => showAppSheet<api.Role>(
    context,
    builder: (context) => const RolePickerSheet(),
  ),
  'member-picker-sheet': (context, ref) => showAppSheet<api.UserProfile>(
    context,
    builder: (context) => const MemberPickerSheet(),
  ),
};

const _viewports = <String, Size>{
  'desktop': Size(1400, 880),
  'phone': Size(390, 844),
};

/// A single route so `GoRouterState.of` and `selectedChannelId` (the pinned
/// messages sheet and the command palette both read the current channel)
/// resolve the same way they would inside the real shell. [open] runs with a
/// real [WidgetRef] straight from [Consumer]'s own builder, never a stand-in.
GoRouter _overlayRouter(
  FutureOr<void> Function(BuildContext, WidgetRef) open,
) => GoRouter(
  initialLocation: '/channels/c-general',
  routes: [
    GoRoute(
      path: '/channels/:channelId',
      builder: (context, state) => Scaffold(
        body: Consumer(
          builder: (context, ref, _) => Center(
            child: TextButton(
              onPressed: () => open(context, ref),
              child: const Text('open overlay'),
            ),
          ),
        ),
      ),
    ),
  ],
);

void main() {
  setUpAll(loadRealFonts);

  for (final viewport in _viewports.entries) {
    for (final overlay in _overlays.entries) {
      testWidgets('${overlay.key} at ${viewport.key} fits its viewport', (
        tester,
      ) async {
        tester.view.physicalSize = viewport.value;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        final fixture = await fixtureContainer();
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: fixture.container,
            child: RepaintBoundary(
              key: snapshotBoundary,
              child: MaterialApp.router(
                debugShowCheckedModeBanner: false,
                theme: buildTheme(Brightness.dark, AppTokens.dark),
                routerConfig: _overlayRouter(overlay.value),
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.tap(find.text('open overlay'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));

        final snapshotName = '${overlay.key}-${viewport.key}';
        await expectSettled(tester, snapshotName);
        await writeSnapshot(tester, snapshotName);

        expect(tester.takeException(), isNull);

        await teardownFixture(tester, fixture.container, fixture.db);
      });
    }
  }
}
