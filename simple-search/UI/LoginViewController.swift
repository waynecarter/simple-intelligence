//
//  LoginViewController.swift
//  simple-search
//
//  Created by Wayne Carter on 6/30/24.
//

import UIKit

class LoginViewController: UIViewController {
    @IBAction func showSettings(_ sender: Any) {
        // When the user chooses to log in, launch the endpoint config settings
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    @IBAction func tryNow(_ sender: Any) {
        // When the user chooses to try now, enable the demo
        Settings.shared.isDemoEnabled = true
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
}
