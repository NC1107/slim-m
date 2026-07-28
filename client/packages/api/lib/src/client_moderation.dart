// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// Report triage and invite management: the `moderation` and `invites` tags
/// that filing a report, checking an invite, and redeeming one (all in
/// client.dart) do not cover.
extension SlimmApiModeration on SlimmApi {
  /// The open moderation queue, oldest first. Requires MANAGE_MESSAGES.
  Future<List<Report>> listOpenReports() async {
    final json = await _send('GET', '/reports');
    return (json as List<dynamic>)
        .map((r) => Report.fromJson(r as Map<String, dynamic>))
        .toList(growable: false);
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
