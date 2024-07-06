//
//  TabBarController.swift
//  simple-intelligence
//
//  Created by Wayne Carter on 6/15/24.
//

import UIKit

class TabBarController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    private func setup() {
        tabBar.tintColor = .label
        tabBar.unselectedItemTintColor = .secondaryLabel
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
}
