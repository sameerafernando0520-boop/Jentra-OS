import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private var privacyCover: UIView?

  override func sceneWillResignActive(_ scene: UIScene) {
    super.sceneWillResignActive(scene)
    guard let window = window, privacyCover == nil else { return }
    let cover = UIView(frame: window.bounds)
    cover.backgroundColor = UIColor(red: 6 / 255, green: 27 / 255, blue: 49 / 255, alpha: 1)
    cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    let label = UILabel(frame: cover.bounds)
    label.text = "Jentra Employee"
    label.textColor = .white
    label.textAlignment = .center
    label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    cover.addSubview(label)
    window.addSubview(cover)
    privacyCover = cover
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    // Flutter keeps the private view locked until online revalidation finishes.
    privacyCover?.removeFromSuperview()
    privacyCover = nil
  }
}
