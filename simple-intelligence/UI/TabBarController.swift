//
//  TabBarController.swift
//  simple-intelligence
//
//  Created by Wayne Carter on 6/15/24.
//

import UIKit
import Combine

class TabBarController: UITabBarController {
    
    private var cancellables = Set<AnyCancellable>()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    private func setup() {
        tabBar.tintColor = .label
        tabBar.unselectedItemTintColor = .secondaryLabel
    }
    
    // MARK: - Full Screen
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
}
