// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The sheet the composer's Apps button opens: the installed apps this caller
/// may launch (from `GET /modules/apps`), each a tap away from being posted
/// into the channel as its interactive, shared surface via
/// [api.SlimmApiMessages.launchAppMessage].
///
/// Nothing here names a module: it lists whatever discovery returns and
/// launches whatever was tapped, per docs/decisions/0021-modules-and-the-dock's
/// module-agnostic principle. [launchApp] is the shared launch path, reused by
/// the composer's `/name` alias so a launch means the same thing either way.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_api/api.dart' as api;
import 'package:slimm_design_system/design_system.dart';

import '../api_failure.dart';
import '../ids.dart';
import '../providers/app_launch.dart';
import '../providers/message_extras.dart';
import '../providers/providers.dart';

/// Launches [app] into [channelId]: posts the message, then applies it to the
/// local store and extras cache exactly as sending a poll does, so the surface
/// appears at once without waiting for the echo. [onError] receives a
/// human-readable message on an API failure; nothing is posted then. Returns
/// whether the launch succeeded, so a caller that typed the launch (the `/name`
/// alias) can keep the text to retry on failure and clear it only on success.
Future<bool> launchApp({
  required WidgetRef ref,
  required String channelId,
  required api.App app,
  void Function(String message)? onError,
}) async {
  try {
    final sent = await ref
        .read(apiProvider)
        .launchAppMessage(
          channelId: channelId,
          id: newMessageId(),
          moduleId: app.moduleId,
          command: app.command,
        );
    final store = await ref.read(storeProvider.future);
    await store.applyMessage(sent);
    ref.read(messageExtrasProvider.notifier).applyMessage(sent);
    return true;
  } on api.ApiException catch (e) {
    onError?.call(describeApiFailure('launch ${app.name}', e));
    return false;
  }
}

/// Opens the apps picker for [channelId]. [onError] is forwarded to [launchApp]
/// so a failed launch surfaces where the composer shows its command errors.
Future<void> showAppLauncherSheet(
  BuildContext context,
  WidgetRef ref,
  String channelId, {
  void Function(String message)? onError,
}) {
  return showAppSheet<void>(
    context,
    builder: (sheetContext) {
      final tokens = Theme.of(sheetContext).extension<AppTokens>()!;
      final apps =
          ref.watch(appLaunchProvider).valueOrNull ?? const <api.App>[];
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s12,
            AppSpacing.s8,
            AppSpacing.s12,
            AppSpacing.s12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (apps.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.s16),
                  child: Text(
                    'No apps to launch. Install one from the Dock first.',
                    style: AppText.caption.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                )
              else
                for (final app in apps)
                  AppListRow(
                    label: app.name,
                    subtitle: app.description,
                    leading: Icon(
                      AppIcons.dock,
                      size: AppSizes.icon16,
                      color: tokens.textSecondary,
                    ),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(
                        launchApp(
                          ref: ref,
                          channelId: channelId,
                          app: app,
                          onError: onError,
                        ),
                      );
                    },
                  ),
            ],
          ),
        ),
      );
    },
  );
}
