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
        
        // When the use case changes, update the UI
        Settings.shared.$useCase
            .dropFirst()
            .sink { [weak self] useCase in
                self?.updateTabBar(useCase: useCase)
            }
            .store(in: &cancellables)
        
        updateTabBar()
    }
    
    private func updateTabBar(useCase: Settings.UseCase = Settings.shared.useCase) {
        switch useCase {
        case .bookingLookup:
            tabBar.isHidden = true
            selectedIndex = 0
        case .itemLookup, .pointOfSale:
            tabBar.isHidden = false
        }
    }
    
    // MARK: - Full Screen
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
}
