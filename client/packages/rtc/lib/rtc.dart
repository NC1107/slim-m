// SPDX-License-Identifier: Apache-2.0
/// LiveKit room and client wrapper behind an explicit public API.
///
/// Everything the app does with media goes through here, so nothing else in
/// the client imports livekit_client or flutter_webrtc directly. That keeps
/// the RTC dependency in one package, and means a widget test can drive a
/// session without a real SFU behind it.
library;

export 'src/broadcast_bridge.dart';
export 'src/media_capabilities.dart';
export 'src/screen_share.dart';
export 'src/voice_session.dart';
