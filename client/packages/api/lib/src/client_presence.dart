// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
part of 'client.dart';

/// Presence: batch status lookup and the caller's own visibility, the
/// `presence` tag.
extension SlimmApiPresence on SlimmApi {
  /// Batch presence lookup, deployment-wide like the member list: any
  /// authenticated caller may ask about any user id. An id with nothing live
  /// to report (never existed, or deleted) is simply absent from the result.
  Future<List<PresenceStatus>> listPresence(List<String> userIds) async {
    final json = await _send(
      'GET',
      '/presence',
      query: {'ids': userIds.join(',')},
    );
    return (json as List<dynamic>)
        .map((p) => PresenceStatus.fromJson(p as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Sets the caller's own visibility preference. Takes effect for every live
  /// viewer at once, not on their next reconnect.
  Future<PresenceVisibility> setPresenceVisibility(
    PresenceVisibility visibility,
  ) async {
    final json = await _send(
      'PATCH',
      '/presence',
      body: {'visibility': visibility.wire},
    );
    return PresenceVisibility.parse(
      (json as Map<String, dynamic>)['visibility'] as String,
    );
  }
}
