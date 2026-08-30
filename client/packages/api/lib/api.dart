// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
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

// The extensions are named here too because `show` filters by declaration
// name: an extension's methods need its own name exported to be in scope.
export 'src/client.dart'
    show
        SlimmApi,
        SessionStore,
        AnalyticsDayCount,
        AnalyticsMemorySample,
        AnalyticsStats,
        MemberAttachmentUsage,
        SpaceAnalytics,
        SlimmApiAdmin,
        SlimmApiAttachments,
        SlimmApiAuth,
        SlimmApiCanvas,
        SlimmApiChannelAdmin,
        SlimmApiDms,
        SlimmApiEmoji,
        SlimmApiGifs,
        SlimmApiMemberModeration,
        SlimmApiMessages,
        SlimmApiModeration,
        SlimmApiPresence,
        SlimmApiPush,
        SlimmApiRoles,
        SlimmApiSpace,
        SlimmApiThreads,
        SlimmApiUsers,
        SlimmApiVoice,
        JoinPolicy;
export 'src/events.dart'
    show
        CanvasCleared,
        CanvasCursorMoved,
        CanvasMediaSlotChanged,
        CanvasObjectMoved,
        CanvasObjectReordered,
        CanvasObjectPlaced,
        CanvasObjectsRemoved,
        CanvasObjectsRestored,
        CanvasStrokePreview,
        CategoryChanged,
        ChannelCreated,
        ChannelDeleted,
        ChannelUpdated,
        EventConnection,
        EventConnectionRefused,
        ErrorEvent,
        HelloEvent,
        MemberRemoved,
        MemberRestored,
        MemberRoleChanged,
        MemberTimeoutChanged,
        MessageCreated,
        MessageDeleted,
        MessageEdited,
        MessagePinned,
        MessageUnpinned,
        OverwriteChanged,
        PollVoted,
        PollOptionTally,
        PongEvent,
        PresenceChanged,
        ProfileChanged,
        ReactionsChanged,
        ReactionTally,
        ReportsChanged,
        RoleChanged,
        ServerEvent,
        ThreadUpdated,
        TypingStarted,
        TypingStopped,
        VoiceActivityChanged,
        protocolVersion;
export 'src/exceptions.dart';
export 'src/limits.dart' show kMessageMaxChars, kUserNoteMaxChars;
export 'src/models.dart';
