//
//  ProductsViewController.swift
//  simple-intelligence
//
//  Created by Wayne Carter on 6/26/24.
//

import UIKit
import Combine

class ProductsViewController: UIViewController {
    @IBOutlet weak var productsView: ProductsView!
    
    @IBOutlet weak var actionsView: UIStackView!
    @IBOutlet weak var actionsView_WidthConstraint: NSLayoutConstraint!
    @IBOutlet weak var actionsView_BottomConstraint: NSLayoutConstraint!
    private var actionsView_BottomConstraint_Constant: CGFloat = 0
    
    @IBOutlet weak var addToBagButton: UIButton!
    @IBOutlet weak var cancelButton: UIButton?
    @IBOutlet weak var doneButton: UIButton?
    
    @IBOutlet weak var infoButton: UIBarButtonItem!
    @IBOutlet weak var shareButton: UIBarButtonItem!
    @IBOutlet weak var payButton: PayBarButtonItem!
    
    private var cancellables = Set<AnyCancellable>()
    
    private func setup() {
        // Cache the original constant for the actions view bottom constraint
        actionsView_BottomConstraint_Constant = actionsView_BottomConstraint.constant
        
        // Set up the cancel button
        cancelButton?.tintColor = .darkGray
        
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
        
        // When the actions view has no visible actions, remove the offset from it's bottom
        // constraint so that the products view will be offset from the bottom a standard amount.
        let visibleActionsCount = actionsView.arrangedSubviews.filter({ $0.isHidden == false }).count
        actionsView_BottomConstraint.constant = visibleActionsCount == 0 ? 0 : actionsView_BottomConstraint_Constant
        // Set the width of the actions bar based on the screen width and number of visible actions.
        let isWidescreen = view.bounds.width > 500
        let widescreenWidth: CGFloat = visibleActionsCount == 1 ? 300 : 390
        actionsView_WidthConstraint.constant = isWidescreen ? widescreenWidth : view.bounds.width - 32
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
