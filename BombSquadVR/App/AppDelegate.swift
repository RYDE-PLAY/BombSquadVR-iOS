import UIKit
import AVFoundation

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    // The engine is process-wide. Keep its view and GL context alive when
    // UIKit disconnects and later reconnects the application's single scene.
    lazy var gameViewController = VRGameViewController()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        application.isIdleTimerDisabled = true
        Self.activateAudioSession()
        return true
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .landscapeRight
    }

    static func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            NSLog("BombSquadVR audio-session activation failed: %@", error.localizedDescription)
        }
    }
}
