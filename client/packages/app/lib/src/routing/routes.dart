// SPDX-License-Identifier: Apache-2.0
/// Route paths, written by hand rather than generated.
///
/// Every navigation goes through these, so a renamed path is a compile error at
/// the call site instead of a string that silently stops matching.
library;

abstract final class Routes {
  static const onboarding = '/join';
  static const signIn = '/sign-in';
  static const channels = '/channels';
  static const settings = '/settings';

  /// The messages of one channel.
  static String channel(String id) => '/channels/$id';

  /// The pattern go_router matches, as distinct from a built path.
  static const channelPattern = '/channels/:channelId';
}
