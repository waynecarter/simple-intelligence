//
//  TextViewController.swift
//  simple-intelligence
//
//  Created by Wayne Carter on 6/24/24.
//

import UIKit
import Combine

class TextViewController: ProductsViewController, UISearchBarDelegate {
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var searchBar_TopConstraint: NSLayoutConstraint!
    
    @IBOutlet weak var explainerView: UIView!
    
    private var cancellables = Set<AnyCancellable>()
    
    private func setup() {
        searchBar.delegate = self
        searchBar.placeholder = "Produce, Bakery, Dairy, and More"
        searchBar.backgroundImage = UIImage()
        searchBar.searchTextField.addTarget(self, action: #selector(searchDidChange(_:)), for: .editingChanged)
    }
    
    private func style() {
        tabBarController?.overrideUserInterfaceStyle = .unspecified
        tabBarController?.tabBar.backgroundColor = .clear
    }
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        style()
    }
    
    // MARK: - Search
    
    private func search(string: String?) {
        if let string {
            products = Database.shared.search(string: string)
        } else {
            products = []
        }
        
        updateExplainer()
    }
    
    private func beginSearch() {
        searchBar.setShowsCancelButton(true, animated: true)
        updateSearchBar(isSearching: true)
    }
    
    private func updateSearchBar(isSearching: Bool) {
        // If there is no space at the top of the screen, we need some to inset the search bar
        let needsSpacing = isSearching && (navigationController?.view.safeAreaInsets.top == 0)
        
        if needsSpacing {
            self.searchBar_TopConstraint.constant = 12
            UIView.animate(withDuration: UINavigationController.hideShowBarDuration) {
                self.view.layoutIfNeeded()
            }
        } else {
            self.searchBar_TopConstraint.constant = 0
            self.view.layoutIfNeeded()
        }
    }
    
    private func endSearch(updateExplainer: Bool = true) {
        updateSearchBar(isSearching: false)
        
        navigationController?.setNavigationBarHidden(false, animated: true)
        
        searchBar.resignFirstResponder()
        searchBar.setShowsCancelButton(false, animated: true)
        searchBar.text = nil
        
        // Clear the products
        products = []
        
        // If specified, update the explainer
        if updateExplainer {
            self.updateExplainer()
        }
    }
    
    @objc func searchDidChange(_ textField: UITextField) {
        search(string: textField.text)
    }
    
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
        beginSearch()
    }
    
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
        // Enable the cancel button when the search bar is not the first responder
        if let cancelButton = searchBar.value(forKey: "cancelButton") as? UIButton {
            // Enable the button sync and async to catch all cases where the button is disabled
            cancelButton.isEnabled = true
            DispatchQueue.main.async {
                cancelButton.isEnabled = true
            }
        }
    }
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        endSearch()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
    
    // MARK: - Actions
    
    override func addToBag(_ sender: UIButton) {
        super.addToBag(sender, beginning: {
            // End search before animating add to bag
            self.endSearch(updateExplainer: false)
        }, completion: {
            // After the animation completes, update the explainer
            self.updateExplainer(animated: true)
        })
    }
    
    override func cancel(_ sender: UIButton) {
        super.cancel(sender)
        endSearch()
    }
    
    // MARK: - Explainer
    
    private func updateExplainer(animated: Bool = false) {
        // When their are products shown hide the explainer, otherwise show it
        UIView.animate(withDuration: animated ? 0.2 : 0) {
            self.explainerView.alpha = self.products.count == 0 ? 1 : 0
        }
    }
}
