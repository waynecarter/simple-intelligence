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
    
    private var mainViewController: UIViewController!
    private var loginViewController: LoginViewController!
    private var isLoggedInListener: AnyCancellable?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)
        self.window = window
        
        // Create the main view controller
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        mainViewController = storyboard.instantiateInitialViewController()!
        
        // Create the login view controller
        loginViewController = storyboard.instantiateViewController(withIdentifier: "LoginViewController") as? LoginViewController
        loginViewController.onLogin = {
            // If the user chooses to log in, launch the endpoint config settings
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        loginViewController.onTryNow = {
            // If the user chooses to try now, enable the demo and show the app
            Settings.shared.isDemoEnabled = true
        }
        
        // If the user is logged in then initially show the main view controller, otherwise
        // show the login view controller
        let initialViewController = Settings.shared.isLoggedIn ? mainViewController : loginViewController
        
        // When the user logs in or enables the demo, show the app
        isLoggedInListener = Settings.shared.$isLoggedIn
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoggedIn in
                guard let self else { return }
                if isLoggedIn {
                    self.transitionRootViewController(to: self.mainViewController)
                } else {
                    self.transitionRootViewController(to: self.loginViewController)
                }
            }
        
        // Show the initial view controller
        window.rootViewController = initialViewController
        window.makeKeyAndVisible()
    }
    
    private func transitionRootViewController(to toViewController: UIViewController) {
        guard let window = self.window,
              let rootViewController = window.rootViewController,
              toViewController != rootViewController else { return }

        // Prepare the toViewController
        toViewController.view.frame = window.bounds

        // Begin transitions for appearance
        rootViewController.beginAppearanceTransition(false, animated: true)
        toViewController.beginAppearanceTransition(true, animated: true)

        // Perform the transition
        UIView.transition(with: window, duration: 0.4, options: [.transitionCrossDissolve, .allowAnimatedContent], animations: {
            let oldAnimationsEnabled = UIView.areAnimationsEnabled
            UIView.setAnimationsEnabled(false)
            
            window.rootViewController = toViewController
            
            UIView.setAnimationsEnabled(oldAnimationsEnabled)
        }, completion: { finished in
            rootViewController.endAppearanceTransition()
            toViewController.endAppearanceTransition()
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

