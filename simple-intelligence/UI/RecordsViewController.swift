//
//  RecordsViewController.swift
//  simple-intelligence
//
//  Created by Wayne Carter on 6/26/24.
//

import UIKit
import Combine

class RecordsViewController: UIViewController {
    @IBOutlet weak var recordsView: RecordsView!
    
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
        
        // When the selected record changes, update the actions
        recordsView.$selectedRecord
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedRecord in
                self?.updateActions(for: selectedRecord)
                self?.updateExternalDisplay(for: selectedRecord)
            }.store(in: &cancellables)
        
        // When the configured use case changes, update the actions
        Settings.shared.$useCase
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] useCase in
                self?.updateActions(for: useCase)
            }.store(in: &cancellables)
        
        // When the external window changes, update the display
        ExternalScene.shared.$window
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] window in
                self?.updateExternalDisplay(in: window)
            }.store(in: &cancellables)
    }
    
    var records: [Database.Record] {
        get {
            return recordsView.records
        }
        set {
            recordsView.records = newValue
            updateExternalDisplay()
        }
    }
    
    // MARK: - View Lifecycle
    
    private var viewIsShowing = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        viewIsShowing = true
        updateActions()
        updateExternalDisplay()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewIsShowing = false
    }
    
    // MARK: - Actions
    
    private func updateActions() {
        updateActions(for: Settings.shared.useCase)
        updateActions(for: recordsView.selectedRecord)
    }
    
    private func updateActions(for useCase: Settings.UseCase) {
        switch useCase {
        case .pointOfSale:
            payButton.total = Database.shared.cartTotal
        case .itemLookup:
            payButton.total = 0
        }
        
        updateActions(for: recordsView.selectedRecord)
    }
    
    private func updateActions(for selectedRecord: Database.Record?) {
        switch Settings.shared.useCase {
        case .pointOfSale:
            if selectedRecord is Database.Booking {
                addToBagButton.isHidden = true
                cancelButton?.isHidden = true
                doneButton?.isHidden = (selectedRecord == nil)
            } else {
                addToBagButton.isHidden = (selectedRecord == nil)
                cancelButton?.isHidden = (selectedRecord == nil)
                doneButton?.isHidden = true
            }
        case .itemLookup:
            addToBagButton.isHidden = true
            cancelButton?.isHidden = true
            doneButton?.isHidden = (selectedRecord == nil)
        }
        
        // When the actions view has no visible actions, remove the offset from it's bottom
        // constraint so that the records view will be offset from the bottom a standard amount.
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
        guard let selectedProduct = recordsView.selectedRecord as? Database.Product,
              let selectedCell = recordsView.selectedCell
        else { return }
        
        Haptics.shared.generateSelectionFeedback()
        Database.shared.addToCart(product: selectedProduct)
        
        beginning?()
        
        // Animate adding the product to the cart
        let navigationController = navigationController as! NavigationController
        let productImageView = selectedCell.imageView
        navigationController.animateAddingImageToRightButtonBarItem(productImageView, from: navigationItem) {
            self.updateActions()
            self.navigationController?.navigationBar.setNeedsLayout()
            completion?()
        }
        
        self.records = []
    }
    
    @IBAction func cancel(_ sender: UIButton) {
        records = []
    }
    
    // MARK: - External Display
    
    private func updateExternalDisplay() {
        updateExternalDisplay(for: recordsView.selectedRecord)
    }
    
    private func updateExternalDisplay(for record: Database.Record?) {
        updateExternalDisplay(for: record, in: ExternalScene.shared.window)
    }
    
    private func updateExternalDisplay(in window: UIWindow?) {
        updateExternalDisplay(for: recordsView.selectedRecord, in: window)
    }
    
    private func updateExternalDisplay(for record: Database.Record?, in window: UIWindow?) {
        // Only update the external display if the view is showing
        guard viewIsShowing else { return }
        
        if let recordViewController = window?.rootViewController as? RecordViewController {
            recordViewController.record = record
            
            recordViewController.view.backgroundColor = view.backgroundColor
            recordViewController.overrideUserInterfaceStyle = tabBarController?.overrideUserInterfaceStyle ?? self.overrideUserInterfaceStyle
            
            // If there is a single record, only display it on the external display
            let onlyDisplayOnExternalScreen = records.count == 1
            recordsView.isHidden = onlyDisplayOnExternalScreen
        } else {
            recordsView.isHidden = false
        }
    }
    
    // MARK: - Full Screen
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
}
