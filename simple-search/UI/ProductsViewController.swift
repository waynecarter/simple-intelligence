//
//  ProductsViewController.swift
//  simple-search
//
//  Created by Wayne Carter on 6/26/24.
//

import UIKit
import Combine

class ProductsViewController: UIViewController {
    @IBOutlet weak var productsView: ProductsView!
    
    @IBOutlet weak var actionsView: UIView!
    @IBOutlet var actionsViewConstraints: [NSLayoutConstraint]!
    @IBOutlet weak var addToBagButton: UIButton!
    @IBOutlet weak var cancelButton: UIButton?
    @IBOutlet weak var doneButton: UIButton?
    
    @IBOutlet weak var infoButton: UIBarButtonItem!
    @IBOutlet weak var shareButton: UIBarButtonItem!
    @IBOutlet weak var payButton: PayBarButtonItem!
    
    private var cancellables = Set<AnyCancellable>()
    
    private func setup() {
        let isWideScreen = view.bounds.width > 500
        
        // For wide screens restrict the width of the actions view
        if isWideScreen {
            NSLayoutConstraint.deactivate(actionsViewConstraints)
            NSLayoutConstraint.activate([
                actionsView.widthAnchor.constraint(equalToConstant: 400),
                actionsView.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            ])
        }
        
        // Set up the cancel button
        if let cancelButton {
            cancelButton.tintColor = .darkGray
        }
        
        // Set up the done button
        if let doneButton {
            doneButton.translatesAutoresizingMaskIntoConstraints = false
            actionsView.addSubview(doneButton)
            
            if isWideScreen {
                NSLayoutConstraint.activate([
                    doneButton.centerXAnchor.constraint(equalTo: actionsView.centerXAnchor),
                    doneButton.centerYAnchor.constraint(equalTo: actionsView.centerYAnchor),
                    doneButton.widthAnchor.constraint(equalToConstant: 300)
                ])
            } else {
                NSLayoutConstraint.activate([
                    doneButton.topAnchor.constraint(equalTo: actionsView.topAnchor),
                    doneButton.leadingAnchor.constraint(equalTo: actionsView.leadingAnchor),
                    doneButton.trailingAnchor.constraint(equalTo: actionsView.trailingAnchor),
                    doneButton.bottomAnchor.constraint(equalTo: actionsView.bottomAnchor)
                ])
            }
        }
        
        updateActions()
        
        // When the selected product changes, update the actions
        productsView.$selectedProduct
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedProduct in
                self?.updateActions(for: selectedProduct)
            }.store(in: &cancellables)
        
        // When the configured use case changes, update the actions
        Settings.shared.$useCase
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] useCase in
                self?.updateActions(for: useCase)
            }.store(in: &cancellables)
    }
    
    var products: [Database.Product] {
        get { return productsView.products }
        set { productsView.products = newValue }
    }
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateActions()
    }
    
    // MARK: - Actions
    
    private func updateActions() {
        updateActions(for: Settings.shared.useCase)
        updateActions(for: productsView.selectedProduct)
    }
    
    private func updateActions(for useCase: Settings.UseCase) {
        switch useCase {
        case .pointOfSale:
            payButton.total = Database.shared.cartTotal
        case .itemLookup:
            payButton.total = 0
        }
        
        updateActions(for: productsView.selectedProduct)
    }
    
    private func updateActions(for selectedProduct: Database.Product?) {
        switch Settings.shared.useCase {
        case .pointOfSale:
            addToBagButton.isHidden = (selectedProduct == nil)
            cancelButton?.isHidden = (selectedProduct == nil)
            doneButton?.isHidden = true
        case .itemLookup:
            addToBagButton.isHidden = true
            cancelButton?.isHidden = true
            doneButton?.isHidden = (selectedProduct == nil)
        }
    }
    
    @IBAction func info(_ sender: UIBarButtonItem) {
        Actions.shared.showInfo(for: self, sourceItem: sender)
    }
    
    @IBAction func share(_ sender: UIBarButtonItem) {
        Actions.shared.showShare(for: self, sourceItem: sender)
    }
    
    @IBAction func pay(_ sender: PayBarButtonItem) {
        Actions.shared.pay(for: self, sourceItem: sender) {
            self.updateActions()
        }
    }
    
    @IBAction func addToBag(_ sender: UIButton) {
        addToBag(sender, beginning: nil, completion: nil)
    }
    
    func addToBag(_ sender: UIButton, beginning: (() -> Void)?, completion: (() -> Void)?) {
        guard let selectedProduct = productsView.selectedProduct,
              let selectedCell = productsView.selectedCell
        else { return }
        
        Haptics.shared.generateSelectionFeedback()
        Database.shared.addToCart(product: selectedProduct)
        self.products = []
        
        beginning?()
        
        // Animate adding the product to the cart
        let navigationController = navigationController as! NavigationController
        let productImageView = selectedCell.imageView
        navigationController.animateAddingImageToRightButtonBarItem(productImageView, from: navigationItem) {
            self.updateActions()
            self.navigationController?.navigationBar.setNeedsLayout()
            completion?()
        }
    }
    
    @IBAction func cancel(_ sender: UIButton) {
        products = []
    }
    
    // MARK: - Full Screen
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
}
