// SPDX-License-Identifier: Apache-2.0
//
// The plaintext inside a sealed push envelope, and what a lock screen should
// make of it.
//
// The authority on this shape is crates/slimm-server/src/push/envelope.rs.
// Everything past the routing fields is optional there: a device that did not
// ask for content, or one whose preview would not fit the envelope budget,
// gets the same envelope with `sender`, `channel` and `body` simply absent.

import Foundation
import UserNotifications

struct PushEnvelope: Decodable {
  /// Domain separation, so a payload sealed to this device in some other
  /// context can never be reinterpreted as a notification.
  static let expectedDomain = "slim-m.push.v1"
  static let expectedVersion = 1

  let domain: String
  let version: Int
  let sender: String?
  let channel: String?
  let body: String?

  /// Decodes, or nil for anything this build should not act on. An unknown
  /// domain or version is refused rather than best-guessed: the generic
  /// string a newer server's envelope falls back to is correct, where a
  /// misread field would put the wrong words on someone's lock screen.
  static func decode(_ plaintext: [UInt8]) -> PushEnvelope? {
    guard let envelope = try? JSONDecoder().decode(
      PushEnvelope.self,
      from: Data(plaintext)
    ) else { return nil }

    guard envelope.domain == expectedDomain,
      envelope.version == expectedVersion
    else { return nil }

    return envelope
  }

  /// Whether there is anything here worth replacing the generic alert with.
  /// A content-free envelope carries the routing fields alone, and rewriting
  /// "New message" into an empty title would be strictly worse than leaving
  /// it be.
  /// An empty body is held to the same bar as an empty sender, and for the
  /// same reason: a message carrying only an attachment has no text at all,
  /// so a preview built from it would replace "New message" with a sender's
  /// name above nothing - less than the placeholder said, not more.
  var hasPreview: Bool {
    guard let sender = sender, !sender.isEmpty else { return false }
    guard let body = body, !body.isEmpty else { return false }
    return true
  }

  /// Rewrites the placeholder in place, leaving everything the relay set -
  /// sound, badge, thread - alone.
  ///
  /// The channel becomes a subtitle rather than part of the title, so a
  /// name too long for one line elides its own line instead of pushing the
  /// sender off the screen. A DM and a thread reply both carry no channel
  /// name at all (the server sends none), so those show the sender alone,
  /// which is already the whole of where it came from.
  func applied(to content: UNMutableNotificationContent) -> UNMutableNotificationContent {
    guard let sender = sender, let body = body else { return content }
    content.title = sender
    if let channel, !channel.isEmpty {
      content.subtitle = "#\(channel)"
    }
    content.body = body
    return content
  }
}
