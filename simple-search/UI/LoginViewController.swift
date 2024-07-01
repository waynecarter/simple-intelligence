//
//  LoginViewController.swift
//  simple-search
//
//  Created by Wayne Carter on 6/30/24.
//

import UIKit

class LoginViewController: UIViewController {
    var onLogin: (() -> Void)?
    var onTryNow: (() -> Void)?
    
    @IBAction func login(_ sender: Any) {
        onLogin?()
    }
    
    @IBAction func tryNow(_ sender: Any) {
        onTryNow?()
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
}
