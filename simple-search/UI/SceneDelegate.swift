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
        
        // Get the main view controller from the storyboard
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        
        // Create the main view controller
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
        
        // If the user logs in or enables the demo, show the app
        isLoggedInListener = Settings.shared.$isLoggedIn
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isLoggedIn in
                guard let self else { return }
                if isLoggedIn {
                    self.transition(from: self.loginViewController, to: self.mainViewController, push: true)
                } else {
                    self.transition(from: mainViewController, to: self.loginViewController)
                }
            }
        
        // Show the initial view controller
        window.rootViewController = initialViewController
        window.makeKeyAndVisible()
    }
    
    private func transition(from fromViewController: UIViewController, to toViewController: UIViewController, push: Bool = false) {
        guard let window, window.rootViewController != toViewController else { return }
        
        // Set up the main view controller frame and layout margins
        toViewController.view.frame = fromViewController.view.frame
        let loginViewLayoutMargins = fromViewController.view.layoutMargins
        let mainViewControlleAdditionalSafeAreaInsets = toViewController.additionalSafeAreaInsets
        toViewController.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0,
            left: loginViewLayoutMargins.left,
            bottom: 0,
            right: loginViewLayoutMargins.right)
        
        // Get a snapshot of the view controllers and add them to the window
        guard let fromSnapshot = fromViewController.view.snapshotView(afterScreenUpdates: true),
              let toSnapshot = toViewController.view.snapshotView(afterScreenUpdates: true)
        else {
            fromViewController.beginAppearanceTransition(false, animated: false)
            toViewController.beginAppearanceTransition(true, animated: false)
            
            window.rootViewController = toViewController
            
            fromViewController.endAppearanceTransition()
            toViewController.endAppearanceTransition()
            
            return
        }
        window.addSubview(fromSnapshot)
        toSnapshot.frame = toViewController.view.frame
        if push {
            toSnapshot.frame.origin.x = fromViewController.view.frame.maxX
        } else {
            toSnapshot.alpha = 0
        }
        window.addSubview(toSnapshot)
        
        // Reset the target view controllers layout margins
        toViewController.additionalSafeAreaInsets = mainViewControlleAdditionalSafeAreaInsets

        // Transition to the target view controller
        UIView.animate(withDuration: 0.2, animations: {
            if push {
                toSnapshot.frame.origin.x = fromViewController.view.frame.origin.x
                fromSnapshot.frame.origin.x -= fromViewController.view.frame.width
            } else {
                toSnapshot.alpha = 0
            }
        }, completion: { _ in
            fromSnapshot.removeFromSuperview()
            toSnapshot.removeFromSuperview()
            
            fromViewController.beginAppearanceTransition(false, animated: false)
            toViewController.beginAppearanceTransition(true, animated: false)
            window.rootViewController = toViewController
            fromViewController.endAppearanceTransition()
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

