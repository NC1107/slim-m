// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// Who may create an account on this deployment.
enum JoinPolicy {
  /// A valid invite code is required. The default, and what every deployment
  /// keeps unless somebody changes it.
  invite,

  /// Anyone who can reach the server may register. A code is still accepted,
  /// so an invite granting a role keeps working.
  open;

  String get wire => name;

  /// An unrecognised policy reads as [invite]. A server that grows a third
  /// value must not read as open to a client that has never heard of it.
  static JoinPolicy parse(String value) =>
      value == 'open' ? JoinPolicy.open : JoinPolicy.invite;
}

/// Deployment-wide settings. Both calls require MANAGE_SERVER.
extension SlimmApiSpace on SlimmApi {
  Future<JoinPolicy> spaceJoinPolicy() async {
    final json = await _send('GET', '/space/settings');
    final map = json as Map<String, dynamic>;
    return JoinPolicy.parse(map['join_policy'] as String);
  }

  Future<JoinPolicy> setSpaceJoinPolicy(JoinPolicy policy) async {
    final json = await _send(
      'PATCH',
      '/space/settings',
      body: {'join_policy': policy.wire},
    );
    final map = json as Map<String, dynamic>;
    return JoinPolicy.parse(map['join_policy'] as String);
  }

  Future<SpaceAnalytics> spaceAnalytics() async {
    final json = await _send('GET', '/space/analytics');
    return SpaceAnalytics._fromJson(json as Map<String, dynamic>);
  }

  Future<SpaceAnalytics> setSpaceAnalyticsEnabled(bool enabled) async {
    final json = await _send(
      'PATCH',
      '/space/analytics',
      body: {'enabled': enabled},
    );
    return SpaceAnalytics._fromJson(json as Map<String, dynamic>);
  }

  Future<int> spaceMessageRetentionDays() async {
    final json = await _send('GET', '/space/retention');
    return (json as Map<String, dynamic>)['retention_days'] as int;
  }

  Future<int> setSpaceMessageRetentionDays(int days) async {
    final json = await _send(
      'PATCH',
      '/space/retention',
      body: {'retention_days': days},
    );
    return (json as Map<String, dynamic>)['retention_days'] as int;
  }
}

/// One calendar day's Space-wide message count, UTC, zero-filled for a day
/// with none.
class AnalyticsDayCount {
  const AnalyticsDayCount({required this.date, required this.count});

  final String date;
  final int count;

  factory AnalyticsDayCount._fromJson(Map<String, dynamic> json) =>
      AnalyticsDayCount(
        date: json['date'] as String,
        count: json['count'] as int,
      );
}

/// One recorded reading of the server process's own memory.
class AnalyticsMemorySample {
  const AnalyticsMemorySample({
    required this.sampledAt,
    required this.rssBytes,
  });

  final int sampledAt;
  final int rssBytes;

  factory AnalyticsMemorySample._fromJson(Map<String, dynamic> json) =>
      AnalyticsMemorySample(
        sampledAt: json['sampled_at'] as int,
        rssBytes: json['rss_bytes'] as int,
      );
}

/// The Space-wide usage stats [SpaceAnalytics] carries when recording is on.
/// Every field here is an aggregate: nothing carries a per-member breakdown,
/// by design - see `docs/decisions/0008-space-analytics.md`.
class AnalyticsStats {
  const AnalyticsStats({
    required this.totalMessages,
    required this.memberCount,
    required this.channelCount,
    required this.attachmentBytes,
    required this.messagesByDay,
    required this.activeHours,
    required this.memorySamples,
  });

  final int totalMessages;
  final int memberCount;
  final int channelCount;
  final int attachmentBytes;
  final List<AnalyticsDayCount> messagesByDay;

  /// 24 entries, index 0-23 as UTC hour-of-day, summed across every author
  /// over the trailing 30-day window.
  final List<int> activeHours;
  final List<AnalyticsMemorySample> memorySamples;

  factory AnalyticsStats._fromJson(Map<String, dynamic> json) => AnalyticsStats(
        totalMessages: json['total_messages'] as int,
        memberCount: json['member_count'] as int,
        channelCount: json['channel_count'] as int,
        attachmentBytes: json['attachment_bytes'] as int,
        messagesByDay: (json['messages_by_day'] as List<dynamic>)
            .map((e) => AnalyticsDayCount._fromJson(e as Map<String, dynamic>))
            .toList(),
        activeHours: (json['active_hours'] as List<dynamic>)
            .map((e) => e as int)
            .toList(),
        memorySamples: (json['memory_samples'] as List<dynamic>)
            .map((e) =>
                AnalyticsMemorySample._fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// One member's own attachment byte total, from [SpaceAnalytics.memberStorage].
///
/// Deliberately not part of [AnalyticsStats]: that class's own doc promises
/// never to name a member, and this is the one field on the response that
/// does, on purpose, for storage stewardship rather than usage surveillance.
/// See `docs/decisions/0008-space-analytics.md`.
class MemberAttachmentUsage {
  const MemberAttachmentUsage({
    required this.userId,
    required this.attachmentBytes,
  });

  final String userId;

  /// Every attachment this member has personally uploaded, by content hash.
  /// Two members who each uploaded identical bytes are each charged the
  /// full size: this is what a member contributed, not a share of
  /// deduplicated disk use.
  final int attachmentBytes;

  factory MemberAttachmentUsage._fromJson(Map<String, dynamic> json) =>
      MemberAttachmentUsage(
        userId: json['user_id'] as String,
        attachmentBytes: json['attachment_bytes'] as int,
      );
}

/// `stats` and `memberStorage` are both null whenever [enabled] is false:
/// recording never ran, so there is nothing to derive or report, not even
/// retroactively. The two are siblings, never nested, on purpose: see
/// [MemberAttachmentUsage]'s own doc for the privacy line between them.
class SpaceAnalytics {
  const SpaceAnalytics({required this.enabled, this.stats, this.memberStorage});

  final bool enabled;
  final AnalyticsStats? stats;
  final List<MemberAttachmentUsage>? memberStorage;

  factory SpaceAnalytics._fromJson(Map<String, dynamic> json) => SpaceAnalytics(
        enabled: json['enabled'] as bool,
        stats: json['stats'] == null
            ? null
            : AnalyticsStats._fromJson(json['stats'] as Map<String, dynamic>),
        memberStorage: json['member_storage'] == null
            ? null
            : (json['member_storage'] as List<dynamic>)
                .map((e) =>
                    MemberAttachmentUsage._fromJson(e as Map<String, dynamic>))
                .toList(),
      );
}
