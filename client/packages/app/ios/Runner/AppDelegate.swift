// SPDX-License-Identifier: Apache-2.0
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Shared with the Dart side; see `packages/platform/lib/src/apns_token_channel.dart`.
  private static let pushChannelName = "top.npcserver.slimm/push"

  private var pushChannel: FlutterMethodChannel?

  // The token or a registration failure can each arrive before Dart has asked
  // for it (a fast relaunch) or long after (the user takes a while to decide
  // on the permission prompt). Caching whichever lands first, and answering
  // "getToken"/"getRegistrationError" from the cache, means neither ordering
  // loses the result.
  private var cachedTokenHex: String?
  private var cachedError: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    requestPushAuthorization(application)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(name: AppDelegate.pushChannelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handlePushCall(call, result: result)
    }
    pushChannel = channel
  }

  private func handlePushCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getToken":
      result(cachedTokenHex)
    case "getRegistrationError":
      result(cachedError)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func requestPushAuthorization(_ application: UIApplication) {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
      // A device token is worth having even if the user declines the alert:
      // the relay still needs it to seal envelopes, and a later notification
      // service extension can act on a silent push without alert permission.
      DispatchQueue.main.async {
        application.registerForRemoteNotifications()
      }
    }
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Data's own string conversion is redacted on modern iOS (something like
    // "32 bytes"), so the hex has to be built by hand, byte by byte.
    let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
    cachedTokenHex = hex
    cachedError = nil
    pushChannel?.invokeMethod("onToken", arguments: hex)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    let message = error.localizedDescription
    cachedError = message
    pushChannel?.invokeMethod("onRegistrationError", arguments: message)
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
