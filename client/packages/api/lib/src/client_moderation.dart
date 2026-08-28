// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// Report triage and invite management: the `moderation` and `invites` tags
/// that filing a report, checking an invite, and redeeming one (all in
/// client.dart) do not cover.
extension SlimmApiModeration on SlimmApi {
  /// One page of the open moderation queue, oldest first. Requires
  /// MANAGE_MESSAGES.
  ///
  /// The cursor is composite and exclusive: pass the `createdAt` *and* `id` of
  /// the last report already held. Both or neither - `createdAt` is
  /// milliseconds, so reports can share one, and a timestamp-only cursor skips
  /// every remaining member of a tied group a page boundary falls inside.
  ///
  /// Channels the caller cannot moderate are excluded server-side before the
  /// limit, not after it, so a short page means the end of the queue and
  /// nothing else.
  Future<List<Report>> listOpenReports({
    int? after,
    String? afterId,
    int? limit,
  }) async {
    final query = <String, String>{
      if (after != null) 'after': '$after',
      if (afterId != null) 'after_id': afterId,
      if (limit != null) 'limit': '$limit',
    };
    final json = await _send(
      'GET',
      '/reports',
      query: query.isEmpty ? null : query,
    );
    return (json as List<dynamic>)
        .map((r) => Report.fromJson(r as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// One page of the merged moderation-history feed: resolved reports and
  /// `moderation_audit_log` entries, newest first. Requires MANAGE_MESSAGES.
  ///
  /// The cursor is composite like [listOpenReports]'s but paged backward:
  /// [after] is the event time of the last item already held (a resolved
  /// report's `resolvedAt`, an audit entry's `createdAt`), [afterKind] is
  /// that item's own [ModerationHistoryItem.cursorKind], and [afterId] is its
  /// [ModerationHistoryItem.id]. All three go together or not at all.
  Future<List<ModerationHistoryItem>> moderationHistory({
    int? after,
    String? afterKind,
    String? afterId,
    int? limit,
  }) async {
    final query = <String, String>{
      if (after != null) 'after': '$after',
      if (afterKind != null) 'after_kind': afterKind,
      if (afterId != null) 'after_id': afterId,
      if (limit != null) 'limit': '$limit',
    };
    final json = await _send(
      'GET',
      '/reports/history',
      query: query.isEmpty ? null : query,
    );
    return (json as List<dynamic>)
        .map((e) => ModerationHistoryItem.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// A reporter's own, narrow view of a report they filed: whether it is
  /// still open. No permission is required beyond having filed it - scoped
  /// hard to the caller's own reports server-side, not by anything this
  /// method checks. Throws [NotFoundException] both for an id that never
  /// existed and for one somebody else filed; the two are indistinguishable
  /// by design, so this cannot tell you which.
  Future<MyReportStatus> myReportStatus(String reportId) async {
    final json = await _send('GET', '/reports/mine/$reportId');
    return MyReportStatus.fromJson(json as Map<String, dynamic>);
  }

  /// Resolves or dismisses a report. Requires MANAGE_MESSAGES. The close is a
  /// conditional update server-side, so two moderators racing the same
  /// report cannot both win it.
  Future<void> resolveReport({
    required String reportId,
    required ReportResolution resolution,
  }) =>
      _send(
        'PATCH',
        '/reports/$reportId',
        body: {'resolution': resolution.wire},
        expectNoContent: true,
      );

  /// Lists every invite. Requires CREATE_INVITE.
  Future<List<Invite>> listInvites() async {
    final json = await _send('GET', '/invites');
    return (json as List<dynamic>)
        .map((i) => Invite.fromJson(i as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Creates an invite. Requires CREATE_INVITE. [maxUses] null means
  /// unlimited; [expiresAt] (Unix milliseconds) null means it never expires.
  /// [roleGrant] needs MANAGE_ROLES on top of CREATE_INVITE, and the role's
  /// permissions must already be held by the caller: an invite that grants a
  /// role is role assignment with a delay.
  Future<Invite> createInvite({
    int? maxUses,
    int? expiresAt,
    String? roleGrant,
  }) async {
    final json = await _send(
      'POST',
      '/invites',
      body: {
        if (maxUses != null) 'max_uses': maxUses,
        if (expiresAt != null) 'expires_at': expiresAt,
        if (roleGrant != null) 'role_grant': roleGrant,
      },
    );
    return Invite.fromJson(json as Map<String, dynamic>);
  }

  /// Revokes an invite. Requires CREATE_INVITE.
  Future<void> revokeInvite(String code) =>
      _send('DELETE', '/invites/$code', expectNoContent: true);
}

/// Moderating a member: a timeout that lapses on its own, and a removal that
/// does not.
///
/// Both refuse on yourself, and on a member whose permissions yours do not
/// already contain - the rule standing in for the role hierarchy this product
/// does not have. Neither is something a client should try to pre-empt beyond
/// hiding the control; the server decides.
extension SlimmApiMemberModeration on SlimmApi {
  /// Times a member out for [duration]. Requires KICK_MEMBERS.
  ///
  /// A timeout takes away sending, reacting, attaching and joining or
  /// speaking in voice, and takes away nothing else: they keep reading.
  /// Returns when it lifts, in Unix milliseconds. Re-issuing replaces any
  /// timeout already in force, which is also how one is shortened.
  Future<int> timeOutMember({
    required String userId,
    required Duration duration,
    String? reason,
  }) async {
    final json = await _send(
      'PUT',
      '/members/$userId/timeout',
      body: {
        'duration_seconds': duration.inSeconds,
        if (reason != null) 'reason': reason,
      },
    );
    return (json as Map<String, dynamic>)['until'] as int;
  }

  /// Lifts a member's timeout. Requires KICK_MEMBERS. Idempotent.
  Future<void> liftMemberTimeout(String userId) => _send(
        'DELETE',
        '/members/$userId/timeout',
        expectNoContent: true,
      );

  /// Removes a member from the Space. Requires BAN_MEMBERS.
  ///
  /// Revokes their sessions, stops them signing in, revokes invites they
  /// handed out, and drops them from the member list. Everything they wrote
  /// stays, still attributed to them.
  Future<void> removeMember({required String userId, String? reason}) => _send(
        'PUT',
        '/members/$userId/removal',
        body: {if (reason != null) 'reason': reason},
        expectNoContent: true,
      );

  /// Lets a removed member back in. Requires BAN_MEMBERS. 404 if they were
  /// not removed, so an undo is distinguishable from a no-op.
  Future<void> restoreMember(String userId) => _send(
        'DELETE',
        '/members/$userId/removal',
        expectNoContent: true,
      );

  /// Every removal in force, newest first. Requires BAN_MEMBERS.
  Future<List<SpaceRemoval>> listRemovedMembers() async {
    final json = await _send('GET', '/members/removed');
    return (json as List<dynamic>)
        .map((r) => SpaceRemoval.fromJson(r as Map<String, dynamic>))
        .toList(growable: false);
  }
}
