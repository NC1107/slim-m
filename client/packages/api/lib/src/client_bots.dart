// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
part of 'client.dart';

/// One bot, as the admin surface lists it. Never carries a token.
class Bot {
  const Bot({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.createdAt,
    this.tokenName,
    this.tokenLastUsedAt,
  });

  factory Bot.fromJson(Map<String, dynamic> json) => Bot(
        userId: json['user_id'] as String,
        username: json['username'] as String,
        displayName: json['display_name'] as String,
        createdAt: json['created_at'] as int,
        tokenName: json['token_name'] as String?,
        tokenLastUsedAt: json['token_last_used_at'] as int?,
      );

  final String userId;
  final String username;
  final String displayName;
  final int createdAt;

  /// Null once the token is revoked, which is how a reader tells a live bot
  /// from one that is only still listed for its authorship.
  final String? tokenName;

  /// Written at most once a minute server-side, so it is a recency hint and
  /// not an exact last-call time.
  final int? tokenLastUsedAt;

  bool get isRevoked => tokenName == null;
}

/// A freshly created bot, and the only time its token is ever legible.
class NewBot {
  const NewBot({required this.bot, required this.token});

  factory NewBot.fromJson(Map<String, dynamic> json) => NewBot(
        bot: Bot.fromJson(json['bot'] as Map<String, dynamic>),
        token: json['token'] as String,
      );

  final Bot bot;

  /// Shown once and unrecoverable afterwards: the server stores only a hash.
  final String token;
}

/// Bots: provisioning, listing and revoking, the `bots` tag.
///
/// All three need MANAGE_SERVER, and creating one additionally needs the caller
/// not to be a bot - see `docs/decisions/0028-bot-accounts.md` for why a bot
/// may not provision a bot.
extension SlimmApiBots on SlimmApi {
  /// Bots in the deployment, newest first. A revoked bot that is still a
  /// member is still listed; one also removed from the Space is not, unless
  /// [includeRemoved] is true - it is already gone from [listMembers].
  Future<List<Bot>> listBots({bool includeRemoved = false}) async {
    final json = await _send(
      'GET',
      '/bots',
      query: includeRemoved ? const {'include_removed': 'true'} : null,
    );
    return (json as List<dynamic>)
        .map((entry) => Bot.fromJson(entry as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Creates a bot and returns it with its token.
  ///
  /// The token is in this response and nowhere else, ever, so a caller that
  /// discards it has to revoke the bot and make another.
  Future<NewBot> createBot(String username, {String? displayName}) async {
    final json = await _send(
      'POST',
      '/bots',
      body: {
        'username': username,
        if (displayName != null) 'display_name': displayName,
      },
    );
    return NewBot.fromJson(json as Map<String, dynamic>);
  }

  /// Revokes a bot's token and session, stopping it on its next request. The
  /// account stays, so what it wrote stays attributed to it.
  Future<void> revokeBot(String botUserId) =>
      _send('POST', '/bots/$botUserId/revoke', expectNoContent: true);
}
