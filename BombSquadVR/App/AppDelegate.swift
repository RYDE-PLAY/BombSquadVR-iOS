import UIKit
import AVFoundation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        application.isIdleTimerDisabled = true
        activateAudioSession()
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = VRGameViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .landscapeRight
    }

    func applicationWillResignActive(_ application: UIApplication) {
        let viewController = window?.rootViewController as? VRGameViewController
        viewController?.pauseRendering()
        BombSquadVRBallisticaHost.shared().setAppActive(false)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BombSquadVRBallisticaHost.shared().suspendApp()
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        BombSquadVRBallisticaHost.shared().unsuspendApp()
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        application.isIdleTimerDisabled = true
        activateAudioSession()
        BombSquadVRBallisticaHost.shared().setAppActive(true)
        (window?.rootViewController as? VRGameViewController)?.resumeRendering()
    }

    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            NSLog("BombSquadVR audio-session activation failed: %@", error.localizedDescription)
        }
    }
}
