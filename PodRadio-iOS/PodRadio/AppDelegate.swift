import UIKit
import AVFoundation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // звук играет в фоне и при заблокированном экране; переключатель «Без звука» его не глушит
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = PlayerViewController()
        window?.makeKeyAndVisible()
        return true
    }
}
