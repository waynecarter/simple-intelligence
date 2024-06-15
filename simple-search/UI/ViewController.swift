//
//  ViewController.swift
//  simple-search
//
//  Created by Wayne Carter on 5/16/24.
//

import UIKit
import Combine

class ViewController: UICollectionViewController {
    private let searchButton = UIButton(type: .custom)
    private let searchTextField = UISearchTextField()
    
    private let payButton = PayButton()
    
    private let selectedItemDetailsLabel = UILabel()
    
    private let addToBagButton = UIButton(type: .roundedRect)
    private let cancelButton = UIButton(type: .roundedRect)
    
    private var addToBagButton_BottomContraint: NSLayoutConstraint!
    private var cartEnabled_Contraints: [NSLayoutConstraint]!
    private var cartDisabled_Contraints: [NSLayoutConstraint]!
    
    private let explainerImageView = UIImageView()
    private let explainerLabel = UILabel()
    
    private let infoButton = UIButton(type: .system)
    
    private let bodyFont = UIFont.preferredFont(forTextStyle: .title3)
    private let explainerActionFont = UIFont.preferredFont(forTextStyle: .title2)
    private let explainerInstructionsFont = UIFont.preferredFont(forTextStyle: .callout)
    
    private let margin: CGFloat = 20
    private let spacing: CGFloat = 10
    
    private var cancellables = Set<AnyCancellable>()
    
    private var products = [Database.Product]() {
        didSet {
            // When the search results change, reload the collection view's data.
            collectionView.reloadData()
            
            // Update the selected item index path and details.
            updateSelectedItemIndexPath()
            updateSelectedItemDetails()
            
            // Update the action buttons.
            updateActions()
        }
    }
    
    init() {
        super.init(collectionViewLayout: CenteredFlowLayout())
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        cancellables.removeAll()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        searchMode = .camera
        
        // When the use-case settings change, update the actions
        Settings.shared.$useCase
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] useCase in
                self?.updateActions(useCase: useCase)
            }.store(in: &cancellables)
        
        // When the settings for the front-facing camera change, update the explainer
        Settings.shared.$frontCameraEnabled
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] frontCameraEnabled in
                self?.updateExplainer(frontCameraEnabled: frontCameraEnabled)
            }.store(in: &cancellables)
        
        // When the authorization for the camera changes, update the explainer
        Camera.shared.$authorized
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authorized in
                self?.updateExplainer(cameraAuthorized: authorized)
            }.store(in: &cancellables)
        
        // When the products from the camera change, update the products
        Camera.shared.$products
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] products in
                self?.products = products
            }.store(in: &cancellables)
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateCollectionViewLayout()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateCollectionViewLayout()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        let searchButtonImageSize: CGFloat = 24
        searchButton.configuration = UIButton.Configuration.plain()
        searchButton.configuration?.buttonSize = .large
        searchButton.configuration?.image = UIImage(systemName: "magnifyingglass")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: searchButtonImageSize))
        searchButton.tintColor = .tertiaryLabel
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        searchButton.addAction(UIAction(title: "Open Search") { [weak self] _ in self?.startTextSearch() }, for: .touchUpInside)
        view.addSubview(searchButton)
        
        searchTextField.placeholder = "Produce, Bakery, Dairy, and More"
        searchTextField.font = bodyFont
        searchTextField.returnKeyType = .done
        
        // Hide the toolbar on the keyboard
        searchTextField.autocorrectionType = .no
        searchTextField.spellCheckingType = .no
        searchTextField.inputAssistantItem.leadingBarButtonGroups = [];
        searchTextField.inputAssistantItem.trailingBarButtonGroups = [];
        
        searchTextField.translatesAutoresizingMaskIntoConstraints = false
        searchTextField.addTarget(self, action: #selector(searchTextFieldDidChange(_:)), for: .editingChanged)
        searchTextField.addTarget(self, action: #selector(searchTextFieldDidEnd(_:)), for: .editingDidEndOnExit)
        searchTextField.alpha = 0
        view.addSubview(searchTextField)
        
        payButton.setTotal(Database.shared.cartTotal, animated: false)
        payButton.addAction(UIAction(title: "Pay") { [weak self] _ in self?.pay() }, for: .touchUpInside)
        payButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(payButton)
        
        collectionView.register(ProductCollectionViewCell.self, forCellWithReuseIdentifier: ProductCollectionViewCell.reuseIdentifier)
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.decelerationRate = .fast
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        if let collectionViewLayout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
            collectionViewLayout.scrollDirection = .horizontal
        }
        
        selectedItemDetailsLabel.adjustsFontForContentSizeCategory = true
        selectedItemDetailsLabel.numberOfLines = 0
        selectedItemDetailsLabel.textAlignment = .center
        selectedItemDetailsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(selectedItemDetailsLabel)
        
        explainerImageView.contentMode = .scaleAspectFit
        explainerImageView.tintColor = .label
        explainerImageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(explainerImageView)
        
        explainerLabel.numberOfLines = 0
        explainerLabel.lineBreakMode = .byWordWrapping
        explainerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(explainerLabel)
        
        addToBagButton.configuration = UIButton.Configuration.filled()
        addToBagButton.configuration?.attributedTitle = "Add to Bag"
        addToBagButton.configuration?.attributedTitle?.font = bodyFont
        addToBagButton.configuration?.buttonSize = .large
        addToBagButton.translatesAutoresizingMaskIntoConstraints = false
        addToBagButton.addAction(UIAction(title: "Add to Bag") { [weak self] _ in self?.addSelectedItemToBag() }, for: .touchUpInside)
        addToBagButton.alpha = 0
        view.addSubview(addToBagButton)
        
        cancelButton.configuration = UIButton.Configuration.filled()
        cancelButton.configuration?.attributedTitle = "Cancel"
        cancelButton.configuration?.attributedTitle?.font = bodyFont
        cancelButton.configuration?.buttonSize = .large
        cancelButton.tintColor = .darkGray
        cancelButton.setContentHuggingPriority(.defaultHigh, for: .horizontal) // Hug the side of the screen during layout.
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addAction(UIAction(title: "Cancel Search") { [weak self] _ in self?.cancelSearch() }, for: .touchUpInside)
        cancelButton.alpha = 0
        view.addSubview(cancelButton)
        
        infoButton.configuration = UIButton.Configuration.plain()
        infoButton.configuration?.image = UIImage(systemName: "info.circle")
        infoButton.configuration?.baseForegroundColor = .tertiaryLabel
        infoButton.translatesAutoresizingMaskIntoConstraints = false
        infoButton.addAction(UIAction(title: "Show Info") { [weak self] _ in self?.showInfo() }, for: .touchUpInside)
        view.addSubview(infoButton)

        let topMargin: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 20 : 0
        NSLayoutConstraint.activate([
            searchButton.centerYAnchor.constraint(equalTo: searchTextField.centerYAnchor),
            searchButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: searchButtonImageSize * 2.25),
            
            searchTextField.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor, constant: topMargin),
            searchTextField.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            searchTextField.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            searchTextField.heightAnchor.constraint(equalTo: payButton.heightAnchor),
            
            payButton.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor, constant: topMargin),
            payButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            
            infoButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            infoButton.bottomAnchor.constraint(equalTo: addToBagButton.bottomAnchor),
            
            collectionView.topAnchor.constraint(equalTo: payButton.bottomAnchor, constant: margin),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: addToBagButton.topAnchor),
            
            selectedItemDetailsLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            selectedItemDetailsLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            selectedItemDetailsLabel.bottomAnchor.constraint(equalTo: addToBagButton.topAnchor, constant: -margin),
            
            explainerImageView.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor, constant: -searchButtonImageSize),
            explainerImageView.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            explainerImageView.widthAnchor.constraint(equalToConstant: 75),
            explainerImageView.heightAnchor.constraint(equalToConstant: 75),
            
            explainerLabel.topAnchor.constraint(equalToSystemSpacingBelow: explainerImageView.bottomAnchor, multiplier: 0.5),
            explainerLabel.centerXAnchor.constraint(equalTo: explainerImageView.centerXAnchor),
            explainerLabel.widthAnchor.constraint(equalToConstant: 320)
        ])

        // Set the width of the add-to-cart and cancel buttons depending on the
        // user interface idiom and whether the cart is enabled.
        addToBagButton_BottomContraint = addToBagButton.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: -margin)
        if UIDevice.current.userInterfaceIdiom == .pad {
            cartEnabled_Contraints = [
                cancelButton.trailingAnchor.constraint(equalTo: addToBagButton.leadingAnchor, constant: -spacing),
                cancelButton.bottomAnchor.constraint(equalTo: addToBagButton.bottomAnchor),
                
                addToBagButton.widthAnchor.constraint(equalToConstant: 300),
                addToBagButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                addToBagButton_BottomContraint
            ]
            
            cartDisabled_Contraints = [
                cancelButton.widthAnchor.constraint(equalToConstant: 300),
                cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                cancelButton.bottomAnchor.constraint(equalTo: addToBagButton.bottomAnchor),
                
                addToBagButton_BottomContraint
            ]
        } else {
            cartEnabled_Contraints = [
                cancelButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
                cancelButton.bottomAnchor.constraint(equalTo: addToBagButton.bottomAnchor),
                
                addToBagButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: spacing),
                addToBagButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
                addToBagButton_BottomContraint
            ]
            
            cartDisabled_Contraints = [
                cancelButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
                cancelButton.bottomAnchor.constraint(equalTo: addToBagButton.bottomAnchor),
                cancelButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
                
                addToBagButton_BottomContraint
            ]
        }
        // Activate the constraints for the add-to-cart and cancel buttons
        let cartEnabled = Settings.shared.useCase == .pointOfSale
        if cartEnabled {
            NSLayoutConstraint.activate(cartEnabled_Contraints)
        } else {
            NSLayoutConstraint.activate(cartDisabled_Contraints)
        }
        
        startExplainerAnimation()
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(notification:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(notification:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    // MARK: - Collection View
    
    private func updateCollectionViewLayout() {
        guard let layout = collectionViewLayout as? UICollectionViewFlowLayout else { return }
        
        let itemSpacing: CGFloat = 30
        layout.minimumLineSpacing = itemSpacing
        
        let maxNumberOfItemsOnScreen: CGFloat = {
            switch UIDevice.current.userInterfaceIdiom {
            case .pad: return 6
            default: return 2
            }
        }()
        
        let itemWidth = floor(collectionView.bounds.width / maxNumberOfItemsOnScreen) - itemSpacing
        let bottomInset = (collectionView.frame.maxY - selectedItemDetailsLabel.frame.minY) + spacing
        let horizontalInset = round(view.bounds.midX - (itemWidth / 2))
        let itemHeight = collectionView.frame.height - bottomInset
        
        layout.itemSize = CGSize(width: itemWidth, height: itemHeight)
        layout.sectionInset = UIEdgeInsets(top: 0, left: horizontalInset, bottom: bottomInset, right: horizontalInset)
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return products.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ProductCollectionViewCell.reuseIdentifier, for: indexPath) as! ProductCollectionViewCell
        let product = products[indexPath.item]
        cell.imageView.image = product.image
        
        return cell
    }
    
    // MARK: - Selected Item
    
    private func updateSelectedItemDetails() {
        if let selectedItemIndexPath = selectedItemIndexPath, products.count > selectedItemIndexPath.item {
            let product = products[selectedItemIndexPath.item]
            
            let attributedString = NSMutableAttributedString(string: product.name + "\n", attributes: [
                .font: UIFont.preferredFont(forTextStyle: .title1),
                .foregroundColor: UIColor.label
            ])
            attributedString.append(NSAttributedString(string:  String(format: "$%.02f", product.price) + "\n", attributes: [
                .font: UIFont.preferredFont(forTextStyle: .title2),
                .foregroundColor: UIColor.label
            ]))
            attributedString.append(NSAttributedString(string: product.location, attributes: [
                .font: UIFont.preferredFont(forTextStyle: .title3),
                .foregroundColor: UIColor.secondaryLabel
            ]))
            
            selectedItemDetailsLabel.attributedText = attributedString
        } else {
            selectedItemDetailsLabel.attributedText = nil
        }
    }
    
    private var selectedItemIndexPath: IndexPath? {
        didSet {
            guard oldValue != selectedItemIndexPath else {
                return
            }
            
            updateSelectedItemDetails()
        }
    }
    
    private func updateSelectedItemIndexPath() {
        guard let layout = collectionViewLayout as? UICollectionViewFlowLayout else {
            return
        }
        
        if products.count == 0 {
            self.selectedItemIndexPath = nil
        } else {
            let contentOffsetX = collectionView.contentOffset.x
            let itemWidth = layout.itemSize.width + layout.minimumLineSpacing
            let itemIndex = Int(round(contentOffsetX / itemWidth))
            let clampedItemIndex = min(max(0, itemIndex), products.count - 1)
                                
            self.selectedItemIndexPath = IndexPath(item: clampedItemIndex, section: 0)
        }
    }
    
    // MARK: - Explainer
    
    private func updateExplainer(frontCameraEnabled: Bool = Settings.shared.frontCameraEnabled, cameraAuthorized: Bool = Camera.shared.authorized) {
        let showExplainer = self.products.count == 0

        explainerImageView.isHidden = !showExplainer
        explainerLabel.isHidden = !showExplainer

        if showExplainer {
            let explainerParagraphStyle = NSMutableParagraphStyle()
            explainerParagraphStyle.alignment = .center
            
            // Set the explainer image
            let imageName: String = {
                if searchMode == .text {
                    return "text.magnifyingglass"
                } else if cameraAuthorized == false {
                    return "info.circle"
                } else {
                    return "dot.viewfinder"
                }
            }()
            let image = UIImage(systemName: imageName)?.withConfiguration(UIImage.SymbolConfiguration(weight: .thin))
            
            // Set the action text
            let actionText: String = {
                if searchMode == .text {
                    return "Search for Item"
                } else if cameraAuthorized == false {
                    return "Enable Camera Access"
                } else {
                    return "Scan an Item"
                }
            }()
            let actionAttributes: [NSAttributedString.Key: Any] = [
                .font: explainerActionFont,
                .foregroundColor: UIColor.label,
                .paragraphStyle: explainerParagraphStyle
            ]
            
            let explainerText = NSMutableAttributedString(string: actionText, attributes: actionAttributes)
            
            // Set instructions text
            let instructionsText: String? = {
                // When searching with the camera, provide additional instructions
                if searchMode == .camera {
                    if cameraAuthorized == false {
                        return "Camera access is not enabled. To use the visual search feature, enable camera access in device settings."
                    } else {
                        return "Position an item in front of the \(frontCameraEnabled ? "front-facing" : "back-facing") camera. The camera is active and scanning."
                    }
                }
                
                return nil
            }()
            if let instructionsText = instructionsText {
                let instructionsAttributes: [NSAttributedString.Key: Any] = [
                    .font: explainerInstructionsFont,
                    .foregroundColor: UIColor.tertiaryLabel,
                    .paragraphStyle: explainerParagraphStyle
                ]
                explainerText.append(NSMutableAttributedString(string: "\n\n\(instructionsText)", attributes: instructionsAttributes))
            }

            UIView.animate(withDuration: 0.6, animations: {
                self.explainerImageView.alpha = 1
                self.explainerLabel.alpha = 1

                self.explainerImageView.image = image
                self.explainerLabel.attributedText = explainerText
            })
        } else {
            UIView.animate(withDuration: 0.2, animations: {
                self.explainerImageView.alpha = 0
                self.explainerLabel.alpha = 0
            }, completion: { _ in
                self.explainerImageView.isHidden = true
                self.explainerLabel.isHidden = true

                self.explainerImageView.image = nil
                self.explainerLabel.text = nil
            })
        }
    }
    
    private func startExplainerAnimation() {
        explainerImageView.layer.masksToBounds = false
        explainerImageView.layer.shadowColor = UIColor.black.cgColor
        explainerImageView.layer.shadowOffset = CGSize(width: 0, height: 2)
        explainerImageView.layer.shadowOpacity = 0
        explainerImageView.layer.shadowRadius = 0
        
        func breathe() {
            // Inhale
            UIView.animate(withDuration: 2, delay: 0, options: [.curveEaseInOut], animations: {
                self.explainerImageView.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
                self.explainerImageView.layer.shadowOpacity = 0.4
                self.explainerImageView.layer.shadowRadius = 4
            }) { _ in
                // Exhale
                UIView.animate(withDuration: 2, delay: 0, options: [.curveEaseInOut], animations: {
                    self.explainerImageView.transform = CGAffineTransform.identity
                    self.explainerImageView.layer.shadowOpacity = 0
                    self.explainerImageView.layer.shadowRadius = 0
                }) { _ in
                    // Repeat
                    breathe()
                }
            }
        }

        breathe()
    }
    
    // MARK: - Add to Bag
    
    private func addSelectedItemToBag() {
        // Get the index path of the active item and add it to the bag.
        guard let selectedItemIndexPath = self.selectedItemIndexPath else {
            return
        }
        
        // Animate the the product image flying into the pay button.
        if let cell = collectionView.cellForItem(at: selectedItemIndexPath) as? ProductCollectionViewCell,
           let window = self.view.window
        {
            // Create a snapshot of the imageView
            let imageView = cell.imageView
            guard let snapshot = imageView.snapshotView(afterScreenUpdates: false) else { return }
            snapshot.frame = window.convert(imageView.frame, from: imageView.superview)
            window.addSubview(snapshot)
            
            // Hide the original imageView temporarily
            imageView.isHidden = true

            // Define the animation path
            let payButtonFrame = window.convert(payButton.frame, from: payButton.superview)
            let finalPoint = CGPoint(x: payButtonFrame.midX, y: payButtonFrame.midY)
            
            UIView.animate(withDuration: 0.5, animations: {
                // Move and scale down the snapshot
                snapshot.center = finalPoint
                snapshot.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
            }, completion: { _ in
                snapshot.removeFromSuperview()
                imageView.isHidden = false
                
                // Set the new cart total.
                self.payButton.setTotal(Database.shared.cartTotal)
            })
        }
        
        // Send force feedback
        self.generateImpactFeedback()
        
        // Add the product to the cart and close the search.
        let product = self.products[selectedItemIndexPath.item]
        Database.shared.addToCart(product: product)
        self.cancelSearch()
    }
    
    // MARK: - Actions
    
    private func updateActions(useCase: Settings.UseCase = Settings.shared.useCase) {
        let cartEnabled = useCase == .pointOfSale
        payButton.isHidden = !cartEnabled
        
        if cartEnabled {
            let showAddToBag = self.searchMode == .text || self.products.count > 0
            let enableAddToBag = self.products.count > 0
            
            addToBagButton.isHidden = !showAddToBag
            addToBagButton.isEnabled = enableAddToBag
            
            if showAddToBag {
                UIView.animate(withDuration: 0.2, animations: {
                    self.addToBagButton.alpha = 1
                })
            } else {
                UIView.animate(withDuration: 0.2, animations: {
                    self.addToBagButton.alpha = 0
                }, completion: { _ in
                    self.addToBagButton.isHidden = true
                })
            }
            
            NSLayoutConstraint.deactivate(cartDisabled_Contraints)
            NSLayoutConstraint.activate(cartEnabled_Contraints)
        } else {
            addToBagButton.isHidden = true
            addToBagButton.isEnabled = true
            
            NSLayoutConstraint.deactivate(cartEnabled_Contraints)
            NSLayoutConstraint.activate(cartDisabled_Contraints)
        }
        
        let showCancel = self.searchMode == .text || self.products.count > 0
        var cancelButtonTitle: AttributedString = cartEnabled || searchMode == .text ? "Cancel" : "Done"
        cancelButtonTitle.font = bodyFont
        cancelButton.configuration?.attributedTitle = cancelButtonTitle
        cancelButton.isHidden = !showCancel
        cancelButton.tintColor = cartEnabled ? .darkGray : nil
        if showCancel {
            UIView.animate(withDuration: 0.2, animations: {
                self.cancelButton.alpha = 1
            })
        } else {
            UIView.animate(withDuration: 0.2, animations: {
                self.cancelButton.alpha = 0
            }, completion: { _ in
                self.cancelButton.isHidden = true
            })
        }
        
        let showInfo = cancelButton.isHidden && addToBagButton.isHidden
        infoButton.isHidden = !showInfo
        
        updateExplainer()
    }
    
    // MARK: - Search
    
    private func cancelSearch() {
        clearSearchResults()
        
        switch searchMode {
        case .camera: startVectorSearch()
        case .text: stopTextSearch()
        }
    }
    
    private func clearSearchResults() {
        if products.count > 0 {
            products = []
        }
    }
    
    enum SearchMode {
        case camera
        case text
    }
    
    private var searchMode: SearchMode = .camera {
        didSet {
            transitionTo(searchMode: searchMode)
        }
    }
    
    private func transitionTo(searchMode: SearchMode) {
        switch searchMode {
        case .camera:
            searchTextField.isHidden = false
            cancelButton.isHidden = false
            searchButton.isHidden = false
            payButton.isHidden = false

            UIView.animate(withDuration: 0.2, animations: {
                self.searchTextField.alpha = 0
                self.cancelButton.alpha = 0
                self.searchButton.alpha = 1
                
                self.payButton.isActive = true
            }, completion: { _ in
                self.searchTextField.isHidden = true
                self.cancelButton.isHidden = true
                
                self.searchTextField.text = nil
            })
            
            searchTextField.resignFirstResponder()
            startVectorSearch()
        case .text:
            stopVectorSearch()
            
            searchTextField.isHidden = false
            cancelButton.isHidden = false
            searchButton.isHidden = false
            payButton.isHidden = false

            UIView.animate(withDuration: 0.2, animations: {
                self.searchTextField.alpha = 1
                self.cancelButton.alpha = 1
                self.searchButton.alpha = 0
                
                self.payButton.isActive = false
            }, completion: { _ in
                self.searchButton.isHidden = true
                self.payButton.isHidden = true
            })
            
            searchTextField.becomeFirstResponder()
        }

        updateActions()
    }
    
    // MARK: - Text Search
    
    private func startTextSearch() {
        searchMode = .text
    }
    
    private func stopTextSearch() {
        clearSearchResults()
        searchMode = .camera
    }
    
    @objc func searchTextFieldDidChange(_ textField: UITextField) {
        if let text = textField.text {
            self.products = Database.shared.search(string: text)
        }
    }
    
    @objc func searchTextFieldDidEnd(_ textField: UITextField) {
        searchTextField.resignFirstResponder()
    }
    
    // MARK: - Vector Search
    
    private func startVectorSearch() {
        Camera.shared.start()
    }
    
    private func stopVectorSearch() {
        Camera.shared.stop()
        clearSearchResults()
    }
    
    // MARK: - Pay
    
    private func pay() {
        searchTextField.resignFirstResponder()
        
        let alert = UIAlertController(title: "Are you sure you want to clear the cart?", message: nil, preferredStyle: .actionSheet)
        alert.popoverPresentationController?.sourceView = payButton
        alert.addAction(UIAlertAction(title: "Clear Cart", style: .destructive, handler: { action in self.clearCart() }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    private func clearCart() {
        Database.shared.clearCart()
        self.payButton.setTotal(0)
        clearSearchResults()
        startVectorSearch()
    }
    
    // MARK: - Info
    
    private func showInfo() {
        Info.shared.show(for: self, sourceView: infoButton)
    }
    
    // MARK: - Scrolling
    
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let oldSelectedItemIndexPath = self.selectedItemIndexPath
        updateSelectedItemIndexPath()
        let newSelectedItemIndexPath = self.selectedItemIndexPath
        
        // If the selected item changed, generated selection feedback
        if oldSelectedItemIndexPath != nil, newSelectedItemIndexPath != oldSelectedItemIndexPath {
            generateSelectionFeedback()
        }
    }
    
    // MARK: - Keyboard
    
    @objc func keyboardWillShow(notification: NSNotification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else {
            return
        }
        
        UIView.animate(withDuration: animationDuration) {
            self.collectionView.performBatchUpdates {
                self.addToBagButton_BottomContraint.constant = self.view.safeAreaInsets.bottom - (keyboardFrame.height + self.margin)
                self.view.layoutIfNeeded()
            }
        }
    }
    
    @objc func keyboardWillHide(notification: NSNotification) {
        guard let userInfo = notification.userInfo,
              let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else {
            return
        }
        
        UIView.animate(withDuration: animationDuration) {
            self.collectionView.performBatchUpdates {
                self.addToBagButton_BottomContraint.constant = -self.margin
                self.view.layoutIfNeeded()
            }
        }
    }
    
    // MARK: - Haptics
    
    private let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()
    
    private func generateImpactFeedback() {
        impactFeedbackGenerator.impactOccurred()
        impactFeedbackGenerator.prepare()
    }
    
    private func generateSelectionFeedback() {
        selectionFeedbackGenerator.selectionChanged()
        selectionFeedbackGenerator.prepare()
    }
    
    // MARK: - Full Screen
    
    private let prefersFullscreen = true
    
    override var prefersStatusBarHidden: Bool {
        // Hide status bar for fullscreen
        return prefersFullscreen
    }
}

class CenteredFlowLayout: UICollectionViewFlowLayout {
    
    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
        let itemWidth = itemSize.width + minimumLineSpacing
        let itemIndex = round(proposedContentOffset.x / itemWidth)
        let newOffsetX = itemWidth * CGFloat(itemIndex)
        return CGPoint(x: newOffsetX, y: proposedContentOffset.y)
    }

}

class ProductCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "ProductCell"
    
    let imageView = UIImageView()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func setup() {
        imageView.contentMode = .scaleAspectFit
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowOffset = CGSize(width: 0, height: 3)
        imageView.layer.shadowOpacity = 0.5
        imageView.layer.shadowRadius = 6
        imageView.layer.masksToBounds = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }
}

class PayButton: UIButton {
    private let font: UIFont = UIFont.preferredFont(forTextStyle: .title3)
    private let boldFont = UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3).withSymbolicTraits(.traitBold)!, size: 0)
    
    private(set) var total: Double = .zero
    
    init() {
        super.init(frame: .zero)
        setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    private func setup() {
        configuration = UIButton.Configuration.filled()
        configuration?.buttonSize = .large
        setTotal(0, animated: false)
    }
    
    func setTotal(_ newTotal: Double, animated: Bool = true) {
        let oldTotal = self.total
        self.total = max(0, newTotal)
        
        if animated == false {
            updateTitle(to: newTotal)
        } else {
            // For tansitioning to a non-zero total, update the title before the animation.
            if newTotal > 0 {
                updateTitle(to: newTotal)
            }
            animate(from: oldTotal, to: newTotal)
        }
    }
    
    private func animate(from oldTotal: Double, to newTotal: Double) {
        guard oldTotal != newTotal else { return }
        
        if newTotal == 0 {
            // Genie exit animation
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseIn], animations: {
                self.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
                self.alpha = 0
            }, completion: { _ in
                self.updateTitle(to: newTotal)
            })
        } else if oldTotal == 0 {
            // Genie bounce entry animation
            self.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 2, options: []) {
                self.transform = CGAffineTransform(scaleX: 1, y: 1)
                self.alpha = 1
            }
        } else {
            // Bounce animation
            UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseInOut], animations: {
                self.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            }, completion: { _ in
                UIView.animate(withDuration: 0.1, delay: 0, options: [.curveEaseIn], animations: {
                    self.transform = CGAffineTransform.identity
                })
            })
        }
    }
    
    private func updateTitle(to total: Double) {
        var title = AttributedString()
        title.append(AttributedString("Pay", attributes: AttributeContainer([.font: boldFont])))

        if total > 0 {
            title.append(AttributedString(String(format: " $%0.2f", total), attributes: AttributeContainer([.font: font])))
        }
        
        self.configuration?.attributedTitle = title
        self.alpha = (total == 0 ? 0 : 1)
    }

    
    var isActive: Bool = true {
        didSet {
            let show = isActive && (total > 0)
            let alpha: CGFloat = show ? 1 : 0
            
            UIView.animate(withDuration: 0.2) {
                self.alpha = alpha
            }
        }
    }
}
