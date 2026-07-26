// SPDX-License-Identifier: Apache-2.0
/// Typed client for the slim-m wire protocol.
///
/// The contract lives in `schema/openapi.yaml`; this package is its Dart side.
/// Two ideas run through it and are worth knowing before use:
///
/// - Identity and order are separate. A message's `id` is a client-generated
///   UUIDv7 that also makes sending idempotent; its `seq` is the server's
///   per-channel order key and the only correct sync cursor.
/// - Writes go over REST and events arrive over the WebSocket. The socket is a
///   fan-out of things that already happened durably, never the write path.
library;

// The extensions must be named in this `show` list too, not just SlimmApi
// itself: `show` filters by declaration name, and an extension's methods are
// only in scope for a caller if the extension's own name is exported, even
// though the caller never spells that name out at the call site.
export 'src/client.dart'
    show
        SlimmApi,
        SessionStore,
        SlimmApiAdmin,
        SlimmApiAttachments,
        SlimmApiChannelAdmin,
        SlimmApiDms,
        SlimmApiMessages,
        SlimmApiModeration,
        SlimmApiPresence,
        SlimmApiRoles,
        SlimmApiUsers;
export 'src/events.dart'
    show
        EventConnection,
        EventConnectionRefused,
        ErrorEvent,
        HelloEvent,
        MessageCreated,
        MessageDeleted,
        MessageEdited,
        MessagePinned,
        MessageUnpinned,
        PollVoted,
        PollOptionTally,
        PongEvent,
        PresenceChanged,
        ReactionsChanged,
        ReactionTally,
        ServerEvent,
        TypingStarted,
        TypingStopped,
        protocolVersion;
export 'src/exceptions.dart';
export 'src/models.dart';
