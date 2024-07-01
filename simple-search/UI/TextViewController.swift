//
//  TextViewController.swift
//  simple-search
//
//  Created by Wayne Carter on 6/24/24.
//

import UIKit
import Combine

class TextViewController: ProductsViewController, UISearchBarDelegate {
    @IBOutlet weak var searchBar: UISearchBar!
    @IBOutlet weak var searchBar_TopConstraint: NSLayoutConstraint!
    var searchBar_TopConstraint_Constant: CGFloat = 0
    
    @IBOutlet weak var explainerView: UIView!
    
    private var cancellables = Set<AnyCancellable>()
    
    private func setup() {
        searchBar.delegate = self
        searchBar.placeholder = "Produce, Bakery, Dairy, and More"
        searchBar.backgroundImage = UIImage()
        searchBar.searchTextField.addTarget(self, action: #selector(searchDidChange(_:)), for: .editingChanged)
        searchBar_TopConstraint_Constant = searchBar_TopConstraint.constant
    }
    
    private func style() {
        tabBarController?.overrideUserInterfaceStyle = .unspecified
        tabBarController?.tabBar.backgroundColor = .clear
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
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
        
        // If there is no space at the top of the screen, add some to inset the search bar
        if let safeAreaInsets = navigationController?.view.safeAreaInsets, safeAreaInsets.top > 0 {
            searchBar_TopConstraint.constant = 0
        } else {
            searchBar_TopConstraint.constant = 12
        }
    }
    
    private func endSearch(updateExplainer: Bool = true) {
        navigationController?.setNavigationBarHidden(false, animated: true)
        
        searchBar.resignFirstResponder()
        searchBar.setShowsCancelButton(false, animated: true)
        searchBar.text = nil
        
        // Reset to the original spacing
        searchBar_TopConstraint.constant = searchBar_TopConstraint_Constant
        
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
    
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        endSearch()
    }
    
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        // Dismiss the keyboard
        searchBar.resignFirstResponder()
        
        // Make sure the cancel button stays enabled even when the search bar is not the first responder
        if let cancelButton = searchBar.value(forKey: "cancelButton") as? UIButton {
            cancelButton.isEnabled = true
        }
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
        // Clear the search
        searchBar.text = nil
    }
    
    // MARK: - Explainer
    
    private func updateExplainer(animated: Bool = false) {
        // When their are products shown hide the explainer, otherwise show it
        UIView.animate(withDuration: animated ? 0.2 : 0) {
            self.explainerView.alpha = self.products.count == 0 ? 1 : 0
        }
    }
}
