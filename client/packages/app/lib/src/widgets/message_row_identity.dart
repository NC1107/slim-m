// SPDX-License-Identifier: Apache-2.0
/// The identity half of a message row: the leading avatar or continuation
/// gutter, and the header line carrying the author name and timestamp.
///
/// Split out of `message_row.dart` to keep that file to the row's own
/// composition; `message_row_parts.dart` is its sibling for the smaller
/// pieces a row can carry beneath the body.
library;

import 'package:flutter/material.dart';
import 'package:slimm_data/data.dart';
import 'package:slimm_design_system/design_system.dart';

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

class MessageRowLeading extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;

    if (grouped) {
      // The continuation gutter: no avatar, just the time, right-aligned to match the avatar it replaces.
      return SizedBox(
        width: _avatarSize,
        child: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            formatMessageTime(message.createdAt),
            textAlign: TextAlign.right,
            style: AppText.micro.copyWith(
              color: tokens.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
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
        name: _authorLabel(message),
        size: _avatarSize,
      ),
    );
  }
}

class MessageRowHeader extends StatelessWidget {
  const MessageRowHeader({
    super.key,
    required this.message,
    required this.isWebhook,
  });

  final Message message;
  final bool isWebhook;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<AppTokens>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _authorLabel(message),
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
          Text(
            formatMessageTime(message.createdAt),
            style: AppText.micro.copyWith(
              color: tokens.textSecondary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Never the raw id: a missing name means the row predates the server
/// sending names, and a 36-character uuid where a person's name goes reads as
/// corruption rather than staleness. A null author id is a deleted account,
/// which is a different and knowable thing.
String _authorLabel(Message message) =>
    message.authorDisplayName ??
    (message.authorId == null ? 'Deleted user' : 'Unknown');
