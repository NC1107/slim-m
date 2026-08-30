// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
import Foundation
import OSLog

/// The two identifiers the app and this extension have to agree on, and the
/// one place either is written down on this side of the App Group boundary.
///
/// `appGroupIdentifier` must match, character for character:
///   - `com.apple.security.application-groups` in both `Runner.entitlements`
///     and `BroadcastExtension.entitlements`, and
///   - `RTCAppGroupIdentifier` in `Runner/Info.plist`, which is what
///     flutter_webrtc's `FlutterBroadcastScreenCapturer` reads to find the
///     same socket from the app side.
///
/// A mismatch is silent: the app opens a socket in one container, this
/// extension connects to a path in another, and the broadcast starts and
/// then produces no frames. The hygiene workflow gates the pair for exactly
/// that reason.
enum BroadcastConstants {
  static let appGroupIdentifier = "group.top.npcserver.slimm"

  /// Named by flutter_webrtc as `kRTCScreensharingSocketFD`; the app creates
  /// the socket at this name inside the shared container.
  static let socketFileName = "rtc_SSFD"
}

let broadcastLogger = OSLog(subsystem: "top.npcserver.slimm", category: "Broadcast")
