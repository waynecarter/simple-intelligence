//
//  ViewController.swift
//  simple-pos
//
//  Created by Wayne Carter on 5/16/24.
//

import UIKit

class ViewController: UICollectionViewController {
    private lazy var database = { return Database.shared }()
    
    private let searchButton = UIButton(type: .custom)
    private let searchTextField = UISearchTextField()
    private let payButton = PayButton()
    private let addToBagButton = UIButton()
    private var addToBagButton_BottomContraint: NSLayoutConstraint!
    
    let labelFontSize = UIFont.labelFontSize * 1.2
    let buttonFontSize = UIFont.labelFontSize * 1.2
    let margin = UIEdgeInsets(top: 8, left: 20, bottom: 20, right: 20)
    
    private var products = [Database.Product]() {
        didSet {
            // When the search results change, reload the collection view's data.
            collectionView.reloadData()
            addToBagButton.isEnabled = (products.count > 0)
        }
    }
    
    init() {
        let layout = CenteredCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        super.init(collectionViewLayout: layout)
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
        searchButton.addAction(UIAction(title: "Open Search") { [weak self] _ in
            self?.openSearch()
        }, for: .touchUpInside)
        view.addSubview(searchButton)
        
        searchTextField.placeholder = "Search"
        let searchTextFont = UIFont.systemFont(ofSize: labelFontSize)
        searchTextField.font = searchTextFont
        searchTextField.isHidden = true
        searchTextField.returnKeyType = .done
        searchTextField.translatesAutoresizingMaskIntoConstraints = false
        searchTextField.addTarget(self, action: #selector(searchTextFieldDidChange(_:)), for: .editingChanged)
        searchTextField.addTarget(self, action: #selector(searchTextFieldDidEnd(_:)), for: .editingDidEndOnExit)
        view.addSubview(searchTextField)
        
        payButton.setTotal(database.cartTotal, animated: false)
        payButton.addAction(UIAction(title: "Pay") { [weak self] _ in
            self?.pay()
        }, for: .touchUpInside)
        payButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(payButton)
        
        addToBagButton.titleLabel?.font = UIFont.systemFont(ofSize: buttonFontSize)
        addToBagButton.configuration = {
            var config = UIButton.Configuration.filled()
            config.title = "Add to Bag"
            config.buttonSize = .large
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: self.buttonFontSize)
                return outgoing
            }
            return config
        }()
        addToBagButton.translatesAutoresizingMaskIntoConstraints = false
        addToBagButton.addAction(UIAction(title: "Add to Bag") { [weak self] _ in self?.addActiveItemToBag() }, for: .touchUpInside)
        addToBagButton.isEnabled = false
        view.addSubview(addToBagButton)
        
        addToBagButton_BottomContraint = addToBagButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -margin.bottom)
        NSLayoutConstraint.activate([
            searchButton.centerYAnchor.constraint(equalTo: searchTextField.centerYAnchor),
            searchButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin.left),
            searchButton.widthAnchor.constraint(equalToConstant: searchButtonImageSize * 2.25),
            
            searchTextField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: margin.top),
            searchTextField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin.left),
            searchTextField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin.right),
            searchTextField.bottomAnchor.constraint(equalTo: payButton.bottomAnchor),
            
            payButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: margin.top),
            payButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin.right),
            
            collectionView.topAnchor.constraint(equalTo: payButton.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: addToBagButton.topAnchor),
            
            addToBagButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: margin.left),
            addToBagButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -margin.right),
            addToBagButton_BottomContraint
            
            // TODO: For iPad, set button width to a constant instead of setting leading and trailing anchors:
            // addToCartButton.widthAnchor.constraint(equalToConstant: 200),
            // addToCartButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            // addToCartButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -margin)
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
    
    func activeProduct() -> Database.Product? {
        let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
        let midPoint = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
        guard let indexPath = collectionView.indexPathForItem(at: midPoint) else {
            return nil
        }
        return self.products[indexPath.item];
    }
    
    func addActiveItemToBag() {
        // Get the index path of the active item and add it to the bag.
        guard let product = activeProduct() else {
            return
        }
        
        // Animate the the product image flying into the pay button.
        let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
        let visibleMidPoint = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
        if let selectedItemIndexPath = collectionView.indexPathForItem(at: visibleMidPoint),
           let cell = collectionView.cellForItem(at: selectedItemIndexPath) as? ProductCollectionViewCell,
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
            let cartButtonFrame = window.convert(payButton.frame, from: payButton.superview)
            let finalPoint = CGPoint(x: cartButtonFrame.midX, y: cartButtonFrame.midY)
            
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
        
        // Add the product to the cart and close the search if it's open
        self.database.addToCart(product: product)
        self.closeSearch()
    }
    
    // MARK: - Search
    
    @objc func searchTextFieldDidChange(_ textField: UITextField) {
        if let text = textField.text {
            self.products = database.search(string: text)
        }
    }
    
    @objc func searchTextFieldDidEnd(_ textField: UITextField) {
        closeSearch()
    }
    
    func openSearch() {
        // TODO: Disable visual search.
        
        searchTextField.alpha = 0
        searchTextField.isHidden = false
        
        searchTextField.becomeFirstResponder()
        
        UIView.animate(withDuration: 0.2, animations: {
            self.searchButton.alpha = 0
            self.searchTextField.alpha = 1
            
            self.payButton.alpha = 0
        }) { _ in
            self.searchButton.isHidden = true
        }
    }
    
    func closeSearch() {
        // TODO: Enable visual search.
        
        clearSearchResult()
        searchTextField.resignFirstResponder()
        
        searchButton.alpha = 0
        searchButton.isHidden = false
        payButton.alpha = 0
        
        UIView.animate(withDuration: 0.2, animations: {
            self.searchButton.alpha = 1
            self.searchTextField.alpha = 0
            
            self.payButton.alpha = 1
        }) { _ in
            self.searchTextField.text = nil
            self.searchTextField.isHidden = true
        }
    }
    
    func clearSearchResult() {
        if products.count > 0 {
            products = []
        }
    }
    
    // MARK: - Payment
    
    func pay() {
        searchTextField.resignFirstResponder()
        
        let dialog = UIAlertController(title: "Payment", message: String(format: "Total $%0.2f", database.cartTotal), preferredStyle: UIAlertController.Style.alert)
        dialog.addAction(UIAlertAction(title: "Clear Cart", style: UIAlertAction.Style.default, handler: { action in self.clearCart() }))
        dialog.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.cancel, handler: nil))
        self.present(dialog, animated: true, completion: nil)
    }
    
    func clearCart() {
        self.database.clearCart()
        self.payButton.setTotal(0)
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
    
    // MARK: - Scrolling
    
    private var selectedItemIndexPath: IndexPath?
    
    override func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let visibleRect = CGRect(origin: collectionView.contentOffset, size: collectionView.bounds.size)
        let visibleMidPoint = CGPoint(x: visibleRect.midX, y: visibleRect.midY)
        let itemIndexPath = collectionView.indexPathForItem(at: visibleMidPoint)
        
        if itemIndexPath?.isEmpty ?? true, products.count > 0 {
            // If the products contain any items then the active product index
            // path can't be null or empty so do nothing. This is expected while
            // scrolling when the midpoint is between items.
        } else {
            // If the selected item changed, generated selection feedback
            if itemIndexPath != nil, selectedItemIndexPath != nil, itemIndexPath != selectedItemIndexPath {
                generateSelectionFeedback()
            }
            
            selectedItemIndexPath = itemIndexPath
        }
    }
    
    override func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard let layout = collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let targetOffset = layout.targetContentOffset(forProposedContentOffset: targetContentOffset.pointee, withScrollingVelocity: velocity)
        targetContentOffset.pointee = targetOffset
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
                self.addToBagButton_BottomContraint.constant = -(keyboardFrame.height + self.margin.bottom) + self.view.safeAreaInsets.bottom
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
                self.addToBagButton_BottomContraint.constant = -self.margin.bottom
                self.view.layoutIfNeeded()
            }
        }
    }
}

class CenteredCollectionViewFlowLayout: UICollectionViewFlowLayout {

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
        guard let collectionView = collectionView else {
            return proposedContentOffset
        }
        
        guard let layoutAttributes = layoutAttributesForElements(in: collectionView.bounds) else {
            return proposedContentOffset
        }
        
        // Find the closest layout to the center point X of the proposedContentOffset
        let collectionViewSize = collectionView.bounds.size
        let proposedContentOffsetCenterX = proposedContentOffset.x + collectionViewSize.width / 2
        
        var closest: UICollectionViewLayoutAttributes?
        for attributes in layoutAttributes {
            if closest == nil || abs(attributes.center.x - proposedContentOffsetCenterX) < abs(closest!.center.x - proposedContentOffsetCenterX) {
                closest = attributes
            }
        }
        
        // Calculate a new content offset from the closet layout
        return CGPoint(x: closest!.center.x - collectionViewSize.width / 2, y: proposedContentOffset.y)
    }
    
    // MARK: - Haptic Feedback
    
    func showTouchButtonFeedback() {
        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.impactOccurred()
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
                self.alpha = 1
            })
        } else if oldTotal == 0 {
            // Genie bounce entry animation
            self.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
            self.alpha = 0
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
        self.isHidden = total == 0
        
        self.sizeToFit()
    }
}
