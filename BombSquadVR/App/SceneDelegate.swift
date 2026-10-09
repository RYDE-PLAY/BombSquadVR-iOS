import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private var gameViewController: VRGameViewController? {
        window?.rootViewController as? VRGameViewController
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene,
              let appDelegate = UIApplication.shared.delegate as? AppDelegate else {
            return
        }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = appDelegate.gameViewController
        self.window = window
        window.makeKeyAndVisible()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        gameViewController?.pauseRendering()
        BombSquadVRBallisticaHost.shared().setAppActive(false)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        BombSquadVRBallisticaHost.shared().suspendApp()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        BombSquadVRBallisticaHost.shared().unsuspendApp()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        UIApplication.shared.isIdleTimerDisabled = true
        AppDelegate.activateAudioSession()
        BombSquadVRBallisticaHost.shared().setAppActive(true)
        gameViewController?.resumeRendering()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        gameViewController?.pauseRendering()
        BombSquadVRBallisticaHost.shared().suspendApp()
        window?.rootViewController = nil
        window = nil
    }
}
