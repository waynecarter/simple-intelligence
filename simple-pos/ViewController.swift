//
//  ViewController.swift
//  simple-pos
//
//  Created by Wayne Carter on 5/16/24.
//

import UIKit

class ViewController: UICollectionViewController, CameraDelegate {
    private lazy var database = { return Database.shared }()
    private lazy var ai = { return AI.shared }()
    
    private let searchButton = UIButton(type: .custom)
    private let searchTextField = UISearchTextField()
    
    private let payButton = PayButton()
    
    private let addToBagButton = UIButton(type: .roundedRect)
    private var addToBagButton_BottomContraint: NSLayoutConstraint!
    private let addToBagButton_BottomMargin: CGFloat = 20
    
    private let cancelButton = UIButton(type: .roundedRect)
    
    private var camera: Camera!
    
    let labelFontSize = UIFont.labelFontSize * 1.2
    let buttonFontSize = UIFont.labelFontSize * 1.2
    
    private var products = [Database.Product]() {
        didSet {
            // When the search results change, reload the collection view's data.
            collectionView.reloadData()
            
            // Update the action buttons.
            updateActions()
            
            // Clear the selected item tracking variable used to detect that
            // the active item has chaged and generate haptic feedback.
            if products.count == 0 { lastSelectedItemIndexPath = nil }
        }
    }
    
    init() {
        let layout = CenteredFlowLayout()
        layout.scrollDirection = .horizontal
        super.init(collectionViewLayout: layout)
        
        camera = Camera(delegate: self)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        startVectorSearch()
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
        collectionView.register(ProductCollectionViewCell.self, forCellWithReuseIdentifier: ProductCollectionViewCell.reuseIdentifier)
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.decelerationRate = .fast
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        
        view.backgroundColor = .systemBackground
        
        let searchButtonImageSize: CGFloat = 24
        searchButton.configuration = UIButton.Configuration.plain()
        searchButton.configuration?.buttonSize = .large
        searchButton.configuration?.image = UIImage(systemName: "magnifyingglass")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: searchButtonImageSize))
        searchButton.tintColor = .label
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        searchButton.addAction(UIAction(title: "Open Search") { [weak self] _ in self?.startTextSearch() }, for: .touchUpInside)
        view.addSubview(searchButton)
        
        searchTextField.placeholder = "Search"
        let searchTextFont = UIFont.systemFont(ofSize: labelFontSize)
        searchTextField.font = searchTextFont
        searchTextField.alpha = 0
        searchTextField.returnKeyType = .done
        searchTextField.translatesAutoresizingMaskIntoConstraints = false
        searchTextField.addTarget(self, action: #selector(searchTextFieldDidChange(_:)), for: .editingChanged)
        searchTextField.addTarget(self, action: #selector(searchTextFieldDidEnd(_:)), for: .editingDidEndOnExit)
        view.addSubview(searchTextField)
        
        payButton.setTotal(database.cartTotal, animated: false)
        payButton.addAction(UIAction(title: "Pay") { [weak self] _ in self?.pay() }, for: .touchUpInside)
        payButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(payButton)
        
        addToBagButton.setTitle("Add to Bag", for: .normal)
        addToBagButton.titleLabel?.font = UIFont.systemFont(ofSize: buttonFontSize)
        addToBagButton.configuration = UIButton.Configuration.filled()
        addToBagButton.configuration?.buttonSize = .large
        addToBagButton.translatesAutoresizingMaskIntoConstraints = false
        addToBagButton.addAction(UIAction(title: "Add to Bag") { [weak self] _ in self?.addActiveItemToBag() }, for: .touchUpInside)
        addToBagButton.alpha = 0
        view.addSubview(addToBagButton)
        
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.tintColor = .darkGray
        cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: buttonFontSize)
        cancelButton.configuration = UIButton.Configuration.filled()
        cancelButton.configuration?.buttonSize = .large
        cancelButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addAction(UIAction(title: "Cancel Search") { [weak self] _ in self?.cancelSearch() }, for: .touchUpInside)
        cancelButton.alpha = 0
        view.addSubview(cancelButton)

        addToBagButton_BottomContraint = addToBagButton.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor, constant: -addToBagButton_BottomMargin)
        NSLayoutConstraint.activate([
            searchButton.centerYAnchor.constraint(equalTo: searchTextField.centerYAnchor),
            searchButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: searchButtonImageSize * 2.25),
            
            searchTextField.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            searchTextField.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            searchTextField.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            searchTextField.bottomAnchor.constraint(equalTo: payButton.bottomAnchor),
            
            payButton.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            payButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            
            collectionView.topAnchor.constraint(equalTo: payButton.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: addToBagButton.topAnchor),
            
            cancelButton.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: addToBagButton.bottomAnchor),
            
            addToBagButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 10),
            addToBagButton.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            addToBagButton_BottomContraint,
            
            // TODO: For iPad, set button width to a constant instead of setting leading and trailing anchors:
            // addToCartButton.widthAnchor.constraint(equalToConstant: 200),
            // addToCartButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            // addToCartButton.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor)
        ])
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(notification:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(notification:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    // MARK: - Collection View
    
    private func updateCollectionViewLayout() {
        guard let layout = collectionViewLayout as? UICollectionViewFlowLayout else { return }
        
        let itemSpacing: CGFloat = 30
        layout.minimumLineSpacing = itemSpacing
        
        // TODO: The itemWidthScalingFactor controls how many items are shown on the screen at once. This should be something like 4.5 on iPad.
        let itemWidthScalingFactor: CGFloat = 1.8
        let itemWidth = (view.bounds.width - (itemSpacing * 2)) / itemWidthScalingFactor
        let itemHeight = itemWidth + 80
        layout.itemSize = CGSize(width: itemWidth, height: itemHeight)
        
        let horizontalInset = view.bounds.midX - (layout.itemSize.width / 2)
        let verticalInset = (collectionView.bounds.height - layout.itemSize.height) / 2
        layout.sectionInset = UIEdgeInsets(top: verticalInset, left: horizontalInset, bottom: verticalInset, right: horizontalInset)
    }
    
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return products.count
    }
    
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ProductCollectionViewCell.reuseIdentifier, for: indexPath) as! ProductCollectionViewCell
        
        let product = products[indexPath.item]
        cell.imageView.image = product.image
        cell.titleLabel.text = product.name
        cell.priceLabel.text = String(format: "$%.02f", product.price)
        cell.locationLabel.text = product.location
        
        return cell
    }
    
    // MARK: - Bag
    
    func addActiveItemToBag() {
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
                self.payButton.setTotal(self.database.cartTotal)
            })
        }
        
        // Send force feedback
        self.generateImpactFeedback()
        
        // Add the product to the cart and close the search.
        let product = self.products[selectedItemIndexPath.item]
        self.database.addToCart(product: product)
        self.cancelSearch()
    }
    
    // MARK: - Search
    
    func cancelSearch() {
        clearSearchResults()
        
        switch searchMode {
        case .vector: startVectorSearch()
        case .text: stopTextSearch()
        }
    }
    
    func clearSearchResults() {
        if products.count > 0 {
            products = []
        }
    }
    
    enum SearchMode {
        case vector
        case text
    }
    
    private var searchMode: SearchMode = .vector {
        didSet {
            transitionTo(searchMode: searchMode)
        }
    }
    
    private func transitionTo(searchMode: SearchMode) {
        switch searchMode {
        case .vector:
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
    
    private func updateActions() {
        let showAddToBag = self.searchMode == .text || self.products.count > 0
        let enableAddToBag = self.products.count > 0
        let showCancel = self.searchMode == .text || self.products.count > 0

        addToBagButton.isHidden = !showAddToBag
        addToBagButton.isEnabled = enableAddToBag
        cancelButton.isHidden = !showCancel

        if showAddToBag {
            addToBagButton.isHidden = false
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

        if showCancel {
            cancelButton.isHidden = false
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
    }
    
    // MARK: - Text Search
    
    func startTextSearch() {
        searchMode = .text
    }
    
    func stopTextSearch() {
        clearSearchResults()
        searchMode = .vector
    }
    
    @objc func searchTextFieldDidChange(_ textField: UITextField) {
        if let text = textField.text {
            self.products = database.search(string: text)
        }
    }
    
    @objc func searchTextFieldDidEnd(_ textField: UITextField) {
        stopTextSearch()
    }
    
    // MARK: - Vector Search
    
    func startVectorSearch() {
        // TODO: Display error if not success (e.g. no permission)
        camera.start { success, error in }
    }
    
    func stopVectorSearch() {
        camera.stop()
        clearSearchResults()
    }
    
    func didCaptureImage(_ image: UIImage) {
        self.ai.foregroundFeatureEmbedding(for: image, fitTo: CGSize(width: 100, height: 100)) { embedding in
            guard let embedding = embedding else { return }
            
            let results = self.database.search(vector: embedding)
            
            // Ignore empty search results
            if results.isEmpty { return }
            
            DispatchQueue.main.async {
                if self.products.isEmpty {
                    self.products = results
                    self.camera.stop()
                }
            }
        }
    }
    
    // MARK: - Pay
    
    func pay() {
        searchTextField.resignFirstResponder()
        
        let alert = UIAlertController(title: "Are you sure you want to clear the cart?", message: nil, preferredStyle: .actionSheet)
        alert.popoverPresentationController?.sourceView = payButton
        alert.addAction(UIAlertAction(title: "Clear Cart", style: .destructive, handler: { action in self.clearCart() }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    func clearCart() {
        self.database.clearCart()
        self.payButton.setTotal(0)
        clearSearchResults()
        startVectorSearch()
    }
    
    // MARK: - Selected Item
    
    private var selectedItemIndexPath: IndexPath? {
        guard let layout = collectionViewLayout as? UICollectionViewFlowLayout else { return nil }
        guard products.count > 0 else { return nil }
        
        // Calculate the currently selected item's index path.
        let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
        let visibleMidPoint = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
        let itemWidth = layout.itemSize.width + layout.minimumLineSpacing
        var itemIndex = Int(round(visibleMidPoint.x / itemWidth)) - 1
        
        // Clamp the item index between 1 and products.count. The calculated index
        // can be invalid when the scroll view has scrolled beyond it's extents.
        itemIndex = min(products.count - 1, itemIndex)
        itemIndex = max(0, itemIndex)
        
        return IndexPath(item: itemIndex, section: 0)
    }
    
    // MARK: - Scrolling
    
    private var lastSelectedItemIndexPath: IndexPath?
    
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let selectedItemIndexPath = self.selectedItemIndexPath
        
        // If the selected item changed, generated selection feedback
        if lastSelectedItemIndexPath != nil, selectedItemIndexPath != lastSelectedItemIndexPath {
            generateSelectionFeedback()
        }
        
        lastSelectedItemIndexPath = selectedItemIndexPath
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
                self.addToBagButton_BottomContraint.constant = -(keyboardFrame.height + self.addToBagButton_BottomMargin) + self.view.safeAreaInsets.bottom
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
                self.addToBagButton_BottomContraint.constant = -self.addToBagButton_BottomMargin
                self.view.layoutIfNeeded()
            }
        }
    }
    
    // MARK: - Haptic Feedback
    
    private let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()
    
    func generateImpactFeedback() {
        impactFeedbackGenerator.impactOccurred()
        impactFeedbackGenerator.prepare()
    }
    
    func generateSelectionFeedback() {
        selectionFeedbackGenerator.selectionChanged()
        selectionFeedbackGenerator.prepare()
    }
}

class CenteredFlowLayout: UICollectionViewFlowLayout {
    
    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
        let itemIndex = round(proposedContentOffset.x / (itemSize.width + minimumLineSpacing))
        let newOffsetX = (itemSize.width + minimumLineSpacing) * CGFloat(itemIndex)
        return CGPoint(x: newOffsetX, y: proposedContentOffset.y)
    }

}

class ProductCollectionViewCell: UICollectionViewCell {
    static let reuseIdentifier = "ProductCell"
    
    let imageView = UIImageView()
    let titleLabel = UILabel()
    let priceLabel = UILabel()
    let locationLabel = UILabel()
    
    let labelFontSize = UIFont.labelFontSize * 1.3
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        // TODO: For iPad, don't show the locationLabel or include it in the layout.
        imageView.contentMode = .scaleAspectFit
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowOffset = CGSize(width: 0, height: 3)
        imageView.layer.shadowOpacity = 0.5
        imageView.layer.shadowRadius = 6
        imageView.layer.masksToBounds = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)
        
        titleLabel.font = UIFont.systemFont(ofSize: labelFontSize, weight: .medium)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        
        priceLabel.font = UIFont.systemFont(ofSize: labelFontSize)
        priceLabel.textAlignment = .center
        priceLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(priceLabel)
        
        locationLabel.textColor = .secondaryLabel
        locationLabel.font = UIFont.systemFont(ofSize: labelFontSize)
        locationLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(locationLabel)
        
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: titleLabel.topAnchor),
            imageView.widthAnchor.constraint(equalTo: contentView.widthAnchor),
            
            titleLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: priceLabel.topAnchor),
            titleLabel.heightAnchor.constraint(equalToConstant: titleLabel.font.lineHeight),
            
            priceLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            priceLabel.bottomAnchor.constraint(equalTo: locationLabel.topAnchor),
            priceLabel.heightAnchor.constraint(equalToConstant: priceLabel.font.lineHeight),
            
            locationLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            locationLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            locationLabel.heightAnchor.constraint(equalToConstant: locationLabel.font.lineHeight)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class PayButton: UIButton {
    private var total: Double = .zero
    
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
        title.append(AttributedString("Pay", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: UIFont.buttonFontSize, weight: .bold)])))
        if total > 0 {
            title.append(AttributedString(String(format: " $%0.2f", total), attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: UIFont.buttonFontSize)])))
        }
        
        self.configuration?.attributedTitle = title
        self.alpha = (total == 0 ? 0 : 1)
        
        self.sizeToFit()
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
