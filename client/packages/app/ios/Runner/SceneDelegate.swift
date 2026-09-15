// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
import Flutter
import UIKit

/// Hides slim-m's content from the iOS task switcher while the biometric app
/// lock is on (`AppLockWindowChannel.shieldEnabled`). The cover has to go up
/// synchronously in `sceneWillResignActive`, before that method returns: the
/// system captures its snapshot right after, and a view added later cannot
/// retroactively hide anything the snapshot already saw.
class SceneDelegate: FlutterSceneDelegate {
  private var privacyShield: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    guard AppLockWindowChannel.shieldEnabled, let window else { return }
    let shield = UIView(frame: window.bounds)
    shield.backgroundColor = .systemBackground
    window.addSubview(shield)
    privacyShield = shield
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    privacyShield?.removeFromSuperview()
    privacyShield = nil
  }
}
