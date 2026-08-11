// SPDX-License-Identifier: Apache-2.0
//
// The Notification Service Extension: given a push before iOS shows it, it
// opens the sealed envelope and replaces the relay's generic "New message"
// with the real sender and text.
//
// The relay never sees any of that. It forwards a base64 blob it cannot read
// (crates/slimm-server/src/push/envelope.rs) and sets `mutable-content` so
// this process gets a chance at it; the fixed placeholder exists precisely so
// a device without this extension still shows something.
//
// Every failure path here shows that placeholder instead. A notification is
// worth showing without its content and is worth nothing at all if it never
// arrives, and this process has a hard time budget and a small memory one, so
// nothing here waits on anything, retries, or reaches the network.

import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
  /// The key the relay puts the sealed envelope under, alongside `kind`, as
  /// a top-level custom field beside `aps`. See the relay's
  /// `internal/apns/apns.go`.
  private static let payloadKey = "payload"

  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var placeholder: UNNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    placeholder = request.content

    // Answered on this call rather than asynchronously: a keychain read
    // and one sealed box are the whole of the work, so there is nothing
    // to wait for and no reason to spend any of the budget waiting.
    deliver(decorated(request.content) ?? request.content)
  }

  /// iOS calls this when the budget runs out, and whatever it is handed is
  /// what the user sees. Reaching it at all would mean `didReceive` never
  /// answered, so the placeholder is the only honest thing left.
  override func serviceExtensionTimeWillExpire() {
    guard let content = placeholder else { return }
    deliver(content)
  }

  /// The handler must be called exactly once; clearing it is what makes a
  /// later `serviceExtensionTimeWillExpire` a no-op rather than a second
  /// call.
  private func deliver(_ content: UNNotificationContent) {
    guard let handler = contentHandler else { return }
    contentHandler = nil
    handler(content)
  }

  /// Nil for anything at all that stops this being a preview worth showing:
  /// no payload, no key on this device yet, a locked keychain, ciphertext
  /// sealed to some other key, an envelope from a version this build does
  /// not know, or one that carried no content in the first place.
  private func decorated(_ content: UNNotificationContent) -> UNNotificationContent? {
    guard let encoded = content.userInfo[Self.payloadKey] as? String,
      let sealed = Data(base64Encoded: encoded),
      let privateKey = PushKeychain.privateKey(),
      let plaintext = PushSealedBox.open([UInt8](sealed), privateKey: privateKey),
      let envelope = PushEnvelope.decode(plaintext),
      envelope.hasPreview,
      let mutable = content.mutableCopy() as? UNMutableNotificationContent
    else { return nil }

    return envelope.applied(to: mutable)
  }
}
