// SPDX-License-Identifier: Apache-2.0
part of 'client.dart';

/// The `auth` tag: everything that starts, rotates, or ends a session.
///
/// Rotation lives here rather than with the transport that triggers it,
/// because what makes it delicate is the token, not the request. The refresh
/// token is single-use, so two rotations in flight at once spend it twice and
/// the server reads the second as a leak and revokes the session. One shared
/// future is what stops that.
extension SlimmApiAuth on SlimmApi {
  /// Creates an account and signs in. On an unclaimed deployment the first
  /// account also becomes its administrator.
  ///
  /// Once a deployment has been claimed, joining it takes an [inviteCode]: the
  /// server spends the code in the same transaction that creates the account,
  /// so there is no separate redeem step to get wrong, and a rejected signup
  /// leaves both the username and the code untouched.
  Future<TokenPair> register({
    required String username,
    required String displayName,
    required String password,
    required String deviceName,
    String? inviteCode,
  }) async {
    final json = await _send(
      'POST',
      '/auth/register',
      authenticated: false,
      body: {
        'username': username,
        'display_name': displayName,
        'password': password,
        'device_name': deviceName,
        if (inviteCode != null) 'invite_code': inviteCode,
      },
    );
    final tokens = TokenPair.fromJson(json as Map<String, dynamic>);
    session.set(tokens);
    return tokens;
  }

  Future<TokenPair> login({
    required String username,
    required String password,
    required String deviceName,
  }) async {
    final json = await _send(
      'POST',
      '/auth/login',
      authenticated: false,
      body: {
        'username': username,
        'password': password,
        'device_name': deviceName,
      },
    );
    final tokens = TokenPair.fromJson(json as Map<String, dynamic>);
    session.set(tokens);
    return tokens;
  }

  /// Rotates the session. Callers rarely need this directly; an unauthorized
  /// response triggers it automatically.
  ///
  /// Concurrent callers share one in-flight rotation: the refresh token is
  /// single-use, so two rotations would spend it twice and the server would
  /// treat the second as a leak and revoke the session.
  Future<TokenPair> refresh() {
    return _refreshInFlight ??= _refreshOnce().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<TokenPair> _refreshOnce() async {
    final current = session.tokens;
    if (current == null) {
      throw const UnauthorizedException('not signed in');
    }
    try {
      final json = await _send(
        'POST',
        '/auth/refresh',
        authenticated: false,
        body: {'refresh_token': current.refreshToken},
      );
      final tokens = TokenPair.fromJson(json as Map<String, dynamic>);
      session.set(tokens);
      return tokens;
    } on UnauthorizedException {
      // The refresh token is spent, revoked, or the session is gone; the only
      // move left is a fresh sign-in.
      session.clear();
      rethrow;
    }
  }

  /// Mints a single-use ticket for opening a WebSocket.
  Future<Ticket> webSocketTicket() async {
    final json = await _send('POST', '/auth/ws-ticket');
    return Ticket.fromJson(json as Map<String, dynamic>);
  }

  /// Ends this session. Any live WebSocket on it is closed by the server.
  Future<void> logout() async {
    await _send('POST', '/auth/logout', expectNoContent: true);
    session.clear();
  }

  /// Deletes the signed-in account. Irreversible.
  Future<void> deleteAccount() async {
    await _send('DELETE', '/account', expectNoContent: true);
    session.clear();
  }
}
