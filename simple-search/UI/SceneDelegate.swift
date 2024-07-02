//
//  SceneDelegate.swift
//  simple-search
//
//  Created by Wayne Carter on 5/16/24.
//

import UIKit
import Combine

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    private lazy var mainViewController: UIViewController = {
        UIStoryboard(name: "Main", bundle: nil).instantiateInitialViewController()!
    }()
    
    private lazy var loginViewController: LoginViewController! = {
        UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "LoginViewController") as! LoginViewController
    }()
    
    private var cancellables = Set<AnyCancellable>()
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window
        
        // If the user is logged in then initially show the main view controller, otherwise
        // show the login view controller
        let initialViewController = Settings.shared.isLoggedIn ? mainViewController : loginViewController
        
        // When the user logs in or out, update the root view controller
        Settings.shared.$isLoggedIn
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoggedIn in
                self?.transitionRootViewController(for: isLoggedIn)
            }
            .store(in: &cancellables)
        
        // Show the initial view controller
        window.rootViewController = initialViewController
        window.makeKeyAndVisible()
    }
    
    private func transitionRootViewController(for isLoggedIn: Bool) {
        guard let window = self.window,
              let oldRootViewController = window.rootViewController,
              let newRootViewController = isLoggedIn ? mainViewController : loginViewController,
              newRootViewController != oldRootViewController
        else { return }

        // Prepare the toViewController
        newRootViewController.view.frame = window.bounds

        // Begin transitions for appearance
        oldRootViewController.beginAppearanceTransition(false, animated: true)
        newRootViewController.beginAppearanceTransition(true, animated: true)

        // Perform the transition
        UIView.transition(with: window, duration: 0.4, options: [.transitionCrossDissolve, .allowAnimatedContent], animations: {
            let oldAnimationsEnabled = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)
            
            window.rootViewController = newRootViewController
            
            UIView.setAnimationsEnabled(oldAnimationsEnabled)
        }, completion: { finished in
            oldRootViewController.endAppearanceTransition()
            newRootViewController.endAppearanceTransition()
        })
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
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

