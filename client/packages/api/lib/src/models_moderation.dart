// SPDX-License-Identifier: Apache-2.0
/// Report triage and invite management.
///
/// Split out of models.dart purely to stay under this repo's line budget; see
/// that file for how the pieces are recombined into one import.
library;

import 'models.dart';

/// A moderation report awaiting triage.
class Report {
  const Report({
    required this.id,
    required this.reporterId,
    required this.subjectKind,
    required this.subjectId,
    required this.channelId,
    required this.reason,
    required this.snapshot,
    required this.createdAt,
  });

  final String id;

  /// Null once the reporter's account has been anonymized.
  final String? reporterId;
  final ReportSubject subjectKind;
  final String subjectId;

  /// Null for a user report, which has no channel of its own.
  final String? channelId;
  final String reason;

  /// The reported content as it stood at filing time. Absent for a user
  /// report; the author may have since edited or deleted it.
  final String? snapshot;

  /// Unix milliseconds.
  final int createdAt;

  factory Report.fromJson(Map<String, dynamic> json) => Report(
        id: json['id'] as String,
        reporterId: json['reporter_id'] as String?,
        subjectKind:
            ReportSubject.values.byName(json['subject_kind'] as String),
        subjectId: json['subject_id'] as String,
        channelId: json['channel_id'] as String?,
        reason: json['reason'] as String,
        snapshot: json['snapshot'] as String?,
        createdAt: json['created_at'] as int,
      );
}

/// How a report was closed.
enum ReportResolution {
  resolved,
  dismissed;

  String get wire => name;
}

/// An invite code.
class Invite {
  const Invite({
    required this.code,
    required this.maxUses,
    required this.uses,
    required this.expiresAt,
    required this.createdAt,
    required this.revoked,
    required this.usable,
    this.roleGrant,
  });

  final String code;

  /// Null means unlimited.
  final int? maxUses;
  final int uses;

  /// Unix milliseconds; null means it never expires.
  final int? expiresAt;

  /// Unix milliseconds.
  final int createdAt;
  final bool revoked;

  /// Whether the invite can be redeemed right now.
  final bool usable;

  /// A role every account redeeming this code receives, or null for none.
  final String? roleGrant;

  factory Invite.fromJson(Map<String, dynamic> json) => Invite(
        code: json['code'] as String,
        maxUses: json['max_uses'] as int?,
        uses: json['uses'] as int,
        expiresAt: json['expires_at'] as int?,
        createdAt: json['created_at'] as int,
        revoked: json['revoked'] as bool,
        usable: json['usable'] as bool,
        roleGrant: json['role_grant'] as String?,
      );
}

/// Whether an invite code can be redeemed right now, and if so, a preview of
/// what it joins.
///
/// A sealed type rather than nullable fields on one flat class, so
/// [InviteUsable.community] is only reachable once a caller has matched that
/// branch: it cannot be read (or accidentally rendered half-populated)
/// without first learning the code actually works. The unusable branch
/// carries no fields at all, mirroring the wire body being exactly
/// `{"usable": false}` whether the code is expired, spent, revoked, or was
/// never issued, so a caller cannot mine codes by branching on why.
sealed class InviteCheck {
  const InviteCheck();

  factory InviteCheck.fromJson(Map<String, dynamic> json) {
    if (json['usable'] != true) return const InviteUnusable();
    return InviteUsable(
      InviteCommunity.fromJson(json['community'] as Map<String, dynamic>),
    );
  }
}

/// The code works right now, and previews the deployment it joins.
class InviteUsable extends InviteCheck {
  const InviteUsable(this.community);

  final InviteCommunity community;
}

/// The code cannot be redeemed. Deliberately carries no reason: expired,
/// spent, revoked, and never-issued are indistinguishable over the wire.
class InviteUnusable extends InviteCheck {
  const InviteUnusable();
}

/// The community metadata an invite discloses, once it is known to be
/// usable. Reaching this already proves the caller holds a working code, so
/// none of this is more than they had already demonstrated.
class InviteCommunity {
  const InviteCommunity({
    required this.name,
    required this.memberCount,
    required this.invitedBy,
    required this.usesRemaining,
    required this.expiresAt,
  });

  /// This deployment's display name.
  final String name;

  /// How many live accounts the deployment has.
  final int memberCount;

  /// The inviter's current display name, or null if their account has since
  /// been deleted.
  final String? invitedBy;

  /// Null means unlimited.
  final int? usesRemaining;

  /// Unix milliseconds; null means it never expires.
  final int? expiresAt;

  factory InviteCommunity.fromJson(Map<String, dynamic> json) =>
      InviteCommunity(
        name: json['name'] as String,
        memberCount: json['member_count'] as int,
        invitedBy: json['invited_by'] as String?,
        usesRemaining: json['uses_remaining'] as int?,
        expiresAt: json['expires_at'] as int?,
      );
}
