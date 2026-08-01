// SPDX-License-Identifier: Apache-2.0
/// The identity half of a message row: the leading avatar or continuation
/// gutter, and the header line carrying the author name and timestamp.
///
/// Split out of `message_row.dart` to keep that file to the row's own
/// composition; `message_row_parts.dart` is its sibling for the smaller
/// pieces a row can carry beneath the body.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

import '../providers/user_profiles.dart';
import 'author_label.dart';
import 'user_avatar.dart';

/// The avatar column's width, and therefore also the continuation gutter's:
/// the design's 36px message-row avatar, named once so both agree.
const double _avatarSize = 36;

/// `HH:mm`, as the design uses throughout. Fixed width matters here: a
/// grouped message puts its time in a 36px gutter, and "12:05 PM" wraps to two
/// lines in it while "12:05" does not.
String formatMessageTime(int epochMs) {
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

const List<String> _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// The label a [DayDivider] carries: "Today" and "Yesterday" for the two days
/// a reader thinks of by name, an absolute date otherwise, and the year only
/// when it is not the current one. [now] is injectable so the relative days
/// are testable without depending on the wall clock.
String formatMessageDay(int epochMs, {DateTime? now}) {
  final dt = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final today = now ?? DateTime.now();
  final thatDay = DateTime(dt.year, dt.month, dt.day);
  final todayDay = DateTime(today.year, today.month, today.day);
  final daysApart = todayDay.difference(thatDay).inDays;
  if (daysApart == 0) return 'Today';
  if (daysApart == 1) return 'Yesterday';
  final month = _monthNames[dt.month - 1];
  return dt.year == today.year
      ? '$month ${dt.day}'
      : '$month ${dt.day}, ${dt.year}';
}

/// The row's time slot, which is also its delivery state: the timestamp once
/// sent, a clock and "sending" while in flight, and a red "not sent" on
/// failure - full strength, because a failed message is still the author's
/// to act on (error grammar 01).
class MessageTimeMark extends StatelessWidget {
  const MessageTimeMark({
    super.key,
    required this.message,
    this.compact = false,
  });

  final Message message;

  /// Glyph-only pending/failed marks, for the 36px continuation gutter where
  /// a word cannot fit.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final mono = AppText.micro.copyWith(
      color: tokens.textSecondary,
      fontFamily: AppFonts.mono,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    if (message.failed) {
      return compact
          ? Icon(AppIcons.failed, size: 11, color: tokens.dangerText)
          : Text('not sent', style: mono.copyWith(color: tokens.dangerText));
    }
    if (message.pending) {
      return compact
          ? Icon(AppIcons.clock, size: 11, color: tokens.textSecondary)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(AppIcons.clock, size: 11, color: tokens.textSecondary),
                const SizedBox(width: 4),
                Text('sending', style: mono),
              ],
            );
    }
    return Text(formatMessageTime(message.createdAt), style: mono);
  }
}

class MessageRowLeading extends ConsumerWidget {
  const MessageRowLeading({
    super.key,
    required this.grouped,
    required this.isWebhook,
    required this.message,
  });

  final bool grouped;
  final bool isWebhook;
  final Message message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    if (grouped) {
      // The continuation gutter: no avatar, just the time, right-aligned to match the avatar it replaces.
      return SizedBox(
        width: _avatarSize,
        child: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: MessageTimeMark(message: message, compact: true),
        ),
      );
    }

    if (isWebhook) {
      return Container(
        width: _avatarSize,
        height: _avatarSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(AppRadii.control),
        ),
        child: Icon(
          AppIcons.code,
          size: AppSizes.icon20,
          color: tokens.textSecondary,
        ),
      );
    }

    // Decorative here: the header beside it already names the author, and
    // without this every message was announced "Ada Lovelace Ada Lovelace".
    return ExcludeSemantics(
      child: AuthorAvatar(
        userId: message.authorId,
        name: _label(ref),
        size: _avatarSize,
      ),
    );
  }

  String _label(WidgetRef ref) => authorLabel(
    authorId: message.authorId,
    cachedDisplayName: message.authorDisplayName,
    profiles: ref.watch(batchProfilesControllerProvider),
  );
}

class MessageRowHeader extends ConsumerWidget {
  const MessageRowHeader({
    super.key,
    required this.message,
    required this.isWebhook,
  });

  final Message message;
  final bool isWebhook;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    final name = authorLabel(
      authorId: message.authorId,
      cachedDisplayName: message.authorDisplayName,
      profiles: ref.watch(batchProfilesControllerProvider),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: AppText.body.copyWith(
                color: tokens.textPrimary,
                fontWeight: AppWeights.semi,
              ),
            ),
          ),
          if (isWebhook) ...[
            const SizedBox(width: AppSpacing.s8),
            const AppBadge(variant: AppBadgeVariant.tag, label: 'webhook'),
          ],
          const SizedBox(width: AppSpacing.s8),
          MessageTimeMark(message: message),
        ],
      ),
    );
  }
}
