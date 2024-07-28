//
//  ExternalSceneDelegate.swift
//  simple-intelligence
//
//  Created by Wayne Carter on 7/28/24.
//

import UIKit
import Combine

class ExternalScene: NSObject {
    static var shared = ExternalScene()
    @Published fileprivate(set) var window: UIWindow?
}

class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    private var cancellables = Set<AnyCancellable>()
    
    private lazy var recordViewController: UIViewController = {
        UIStoryboard(name: "ExternalScreen", bundle: nil).instantiateInitialViewController()!
    }()
    
    override init() {
        super.init()
        setup()
    }
    
    private func setup() {
        // When the external screen is enabled/disable, update the external screen
        Settings.shared.$externalScreenEnabled
            .dropFirst()
            .sink { [weak self] externalScreenEnabled in
                self?.setupExternalScreen(externalScreenEnabled: externalScreenEnabled)
            }.store(in: &cancellables)
    }
    
    // MARK: - External Screen
    
    private func setupExternalScreen(externalScreenEnabled: Bool = Settings.shared.externalScreenEnabled) {
        guard externalScreenEnabled else {
            tearDownExternalScreen()
            return
        }
        
        // Show the root view controller
        window?.rootViewController = recordViewController
        window?.makeKeyAndVisible()
        
        // Connect the external scene's window
        ExternalScene.shared.window = window
    }
    
    private func tearDownExternalScreen() {
        ExternalScene.shared.window?.isHidden = true
        ExternalScene.shared.window = nil
    }
    
    // MARK: - Scene
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Get the window from the scene
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        self.window = window
        
        // Setup external screen
        setupExternalScreen()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Disconnect external screen
        tearDownExternalScreen()
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }
}
