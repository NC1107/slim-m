// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
part of 'client.dart';

/// Profiles, the caller's own account, and the deployment's member list: the
/// `users` tag in schema/openapi.yaml.
extension SlimmApiUsers on SlimmApi {
  /// The caller's own profile and base (deployment-level) permissions.
  Future<Me> me() async {
    final json = await _send('GET', '/me');
    return Me.fromJson(json as Map<String, dynamic>);
  }

  /// Updates the caller's own display name and/or status line. Both are
  /// optional, null meaning "leave it as it is" - a call naming neither
  /// throws a 400. Pass an empty string for [statusText] to clear it back to
  /// none, the same "blank clears it" convention `updateChannel`'s `topic`
  /// uses. The username is not editable here: it backs the live per-account
  /// uniqueness index, so changing it needs a dedicated flow that can handle
  /// the resulting collision.
  Future<UserProfile> updateMe(
      {String? displayName, String? statusText}) async {
    final json = await _send(
      'PATCH',
      '/me',
      body: {
        if (displayName != null) 'display_name': displayName,
        if (statusText != null) 'status_text': statusText,
      },
    );
    return UserProfile.fromJson(json as Map<String, dynamic>);
  }

  /// Batch-fetches public profiles by id. An id with nothing live to report
  /// (never existed, or deleted) is simply absent from the result, so match
  /// by id rather than by position.
  Future<List<UserProfile>> listUsers(List<String> ids) async {
    final json = await _send(
      'GET',
      '/users',
      query: ids.isEmpty ? null : {'ids': ids.join(',')},
    );
    return (json as List<dynamic>)
        .map((u) => UserProfile.fromJson(u as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// A single public profile. A deleted or anonymized account answers 404,
  /// exactly like an id that was never used, so this cannot confirm someone
  /// deleted their account.
  Future<UserProfile> getUser(String userId) async {
    final json = await _send('GET', '/users/$userId');
    return UserProfile.fromJson(json as Map<String, dynamic>);
  }

  /// The deployment's members, oldest first. Deployment-wide rather than
  /// scoped to a channel, so any authenticated caller may read it. Keyset
  /// paginated on id; pass the last id seen as [after] for the next page.
  Future<List<UserProfile>> listMembers({String? after, int? limit}) async {
    final query = <String, String>{
      if (after != null) 'after': after,
      if (limit != null) 'limit': '$limit',
    };
    final json = await _send(
      'GET',
      '/members',
      query: query.isEmpty ? null : query,
    );
    return (json as List<dynamic>)
        .map((u) => UserProfile.fromJson(u as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Uploads (or replaces) the caller's avatar with raw [bytes]. One mutable
  /// image per user, replaced wholesale: unlike [SlimmApi.uploadAttachment]
  /// this is never content-addressed and no channel permission gates it.
  Future<UserProfile> uploadAvatar(List<int> bytes) async {
    final json = await _send('POST', '/me/avatar', bytes: bytes);
    return UserProfile.fromJson(json as Map<String, dynamic>);
  }

  /// Removes the caller's avatar. Not an error if there was none.
  Future<void> deleteAvatar() =>
      _send('DELETE', '/me/avatar', expectNoContent: true);

  /// Fetches a user's avatar bytes. Gated on authentication only: an avatar
  /// is a public profile picture, not a message attachment, so no channel
  /// permission applies.
  Future<FetchedBytes> fetchAvatar(String userId) =>
      _fetchBytes('/users/$userId/avatar');
}
