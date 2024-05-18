//
//  ViewController.swift
//  simple-pos
//
//  Created by Wayne Carter on 5/16/24.
//

import UIKit

class ViewController: UICollectionViewController {
    private let searchBar = UIView()
    private let searchButton = UIButton(type: .custom)
    private let searchTextField = UITextField()
    private let searchCloseButton = UIButton(type: .custom)
    private let payButton = UIButton(type: .custom)
    private let addToBagButton = UIButton()
    private var addToBagButtonBottomContraint: NSLayoutConstraint!
    
    let labelFontSize = UIFont.labelFontSize * 1.2
    let buttonFontSize = UIFont.labelFontSize * 1.2
    let margin = UIEdgeInsets(top: 8, left: 20, bottom: 20, right: 20)
    
    let products = [
        ("Bell Pepper", "🫑", "$2.00", "Isle 5"),
        ("Broccoli", "🥦", "$1.50", "Isle 2"),
        ("Lettuce", "🥬", "$1.00", "Isle 4"),
        ("Cucumber", "🥒", "$1.20", "Isle 3"),
        ("Green Apple", "🍏", "$2.50", "Isle 6"),
        ("Avocado", "🥑", "$2.80", "Isle 1")
    ]
    
    init() {
        let layout = UICollectionViewFlowLayout()
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
        view.backgroundColor = .systemBackground
        
        searchBar.layer.cornerRadius = 10
        searchBar.layer.masksToBounds = true
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)
        
        let searchButtonImageSize: CGFloat = 24
        searchButton.configuration = {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: "magnifyingglass")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: searchButtonImageSize))
            return config
        }()
        searchButton.tintColor = .label
        searchButton.translatesAutoresizingMaskIntoConstraints = false
        searchButton.addAction(UIAction(title: "Open Search") { [weak self] _ in
            self?.openSearch()
        }, for: .touchUpInside)
        searchBar.addSubview(searchButton)
        
        searchCloseButton.configuration = {
            var config = UIButton.Configuration.plain()
            config.image = UIImage(systemName: "xmark")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: searchButtonImageSize))
            return config
        }()
        searchCloseButton.tintColor = .label
        searchCloseButton.isHidden = true
        searchCloseButton.translatesAutoresizingMaskIntoConstraints = false
        searchCloseButton.addAction(UIAction(title: "Close Search") { [weak self] _ in
            self?.closeSearch()
        }, for: .touchUpInside)
        searchBar.addSubview(searchCloseButton)
        
        searchTextField.placeholder = "Search"
        let searchTextFont = UIFont.systemFont(ofSize: labelFontSize)
        searchTextField.font = searchTextFont
        searchTextField.isHidden = true
        searchTextField.translatesAutoresizingMaskIntoConstraints = false
        searchTextField.addTarget(self, action: #selector(searchTextFieldDidChange(_:)), for: .editingChanged)
        searchBar.addSubview(searchTextField)
        
        payButton.configuration = {
            var config = UIButton.Configuration.filled()
            config.buttonSize = .large
            config.attributedTitle = {
                var title = AttributedString()
                title.append(AttributedString("Pay", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: buttonFontSize, weight: .bold)])))
                title.append(AttributedString(" $30.50", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: buttonFontSize)])))
                return title
            }()
            return config
        }()
        payButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(payButton)
        
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(ProductCollectionViewCell.self, forCellWithReuseIdentifier: ProductCollectionViewCell.reuseIdentifier)
        
        addToBagButton.titleLabel?.font = UIFont.systemFont(ofSize: buttonFontSize)
        addToBagButton.configuration = {
            var config = UIButton.Configuration.filled()
            config.buttonSize = .large
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: self.buttonFontSize)
                return outgoing
            }
            config.title = "Add to Bag"
            return config
        }()
        addToBagButton.translatesAutoresizingMaskIntoConstraints = false
        addToBagButton.addAction(UIAction(title: "Add to Bag") { [weak self] _ in self?.addActiveItemToBag() }, for: .touchUpInside)
        view.addSubview(addToBagButton)
        
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        
        let spacing: CGFloat = 10
        addToBagButtonBottomContraint = addToBagButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -margin.bottom)
        NSLayoutConstraint.activate([
            searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: margin.top),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: margin.left),
            searchBar.trailingAnchor.constraint(equalTo: payButton.leadingAnchor, constant: -spacing),
            searchBar.bottomAnchor.constraint(equalTo: payButton.bottomAnchor),
            
            searchButton.topAnchor.constraint(equalTo: searchBar.topAnchor),
            searchButton.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor),
            searchButton.bottomAnchor.constraint(equalTo: searchBar.bottomAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: searchButtonImageSize * 2.25),
            
            searchCloseButton.topAnchor.constraint(equalTo: searchBar.topAnchor),
            searchCloseButton.leadingAnchor.constraint(equalTo: searchBar.leadingAnchor),
            searchCloseButton.bottomAnchor.constraint(equalTo: searchBar.bottomAnchor),
            searchCloseButton.widthAnchor.constraint(equalToConstant: searchButtonImageSize * 2.25),
            
            searchTextField.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            searchTextField.leadingAnchor.constraint(equalTo: searchCloseButton.trailingAnchor),
            searchTextField.trailingAnchor.constraint(equalTo: searchBar.trailingAnchor, constant: -spacing),
            searchTextField.heightAnchor.constraint(equalToConstant: searchTextFont.lineHeight + searchTextFont.ascender + searchTextFont.descender + searchTextFont.leading),
            
            payButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: margin.top),
            payButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -margin.right),
            
            collectionView.topAnchor.constraint(equalTo: payButton.bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: addToBagButton.topAnchor),
            
            addToBagButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: margin.left),
            addToBagButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -margin.right),
            addToBagButtonBottomContraint
            
            // TODO: For iPad, set button width to a constant instead of setting leading and trailing anchors:
            // addToCartButton.widthAnchor.constraint(equalToConstant: 200),
            // addToCartButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            // addToCartButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -margin)
        ])
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(notification:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(notification:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
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
        cell.imageView.image = UIImage.from(string: product.1)
        cell.titleLabel.text = product.0
        cell.priceLabel.text = product.2
        cell.locationLabel.text = product.3
        
        return cell
    }
    
    func addActiveItemToBag() {
        // TODO: Get the index path of the active item and add it to the bag.
        // TODO: Update the payButton with the new bag total.
        // TODO: Should we also close the search? If so, calling closeSearch() will close it if it's open.
    }
    
    @objc func searchTextFieldDidChange(_ textField: UITextField) {
        // TODO: Execute the search and update the search results.
    }
    
    func openSearch() {
        guard searchTextField.isHidden == true else { return }
        
        // TODO: Disable visual search.
        
        UIView.transition(with: searchBar, duration: 0.2, options: .transitionCrossDissolve) { [self] in
            searchBar.backgroundColor = .secondarySystemBackground
            searchButton.isHidden = true
            searchCloseButton.isHidden = false
            searchTextField.isHidden = false
            searchTextField.becomeFirstResponder()
        }
    }
    
    func closeSearch() {
        guard searchTextField.isHidden == false else { return }
        
        UIView.transition(with: searchBar, duration: 0.2, options: .transitionCrossDissolve) { [self] in
            searchBar.backgroundColor = nil
            searchButton.isHidden = false
            searchCloseButton.isHidden = true
            searchTextField.isHidden = true
            searchTextField.text = nil
            searchTextField.resignFirstResponder()
        }
        
        // TODO: Enable visual search.
    }
    
    @objc func keyboardWillShow(notification: NSNotification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let animationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval else {
            return
        }
        
        UIView.animate(withDuration: animationDuration) {
            self.collectionView.performBatchUpdates {
                self.addToBagButtonBottomContraint.constant = -(keyboardFrame.height + self.margin.bottom) + self.view.safeAreaInsets.bottom
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
                self.addToBagButtonBottomContraint.constant = -self.margin.bottom
                self.view.layoutIfNeeded()
            }
        }
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

extension UIImage {
    static func from(string: String) -> UIImage {
        let nsString = string as NSString
        let font = UIFont.systemFont(ofSize: 160)
        let stringAttributes = [NSAttributedString.Key.font: font]
        let imageSize = nsString.size(withAttributes: stringAttributes)

        let renderer = UIGraphicsImageRenderer(size: imageSize)
        let image = renderer.image { _ in
            nsString.draw( at: CGPoint.zero, withAttributes: stringAttributes)
        }

        return image
    }
}
