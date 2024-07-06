//
//  HorizontalCollectionView.swift
//  simple-intelligence
//
//  Created by Wayne Carter on 6/23/24.
//

import UIKit
import Combine

class ProductsView: UIView {
    let collectionView = CollectionView()
    let detailsLabel = UILabel()
    
    let explainerImageView = UIImageView()
    let explainerLabel = UILabel()
    
    private var cancellables = Set<AnyCancellable>()
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        collectionView.backgroundColor = self.backgroundColor
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(collectionView)
        
        detailsLabel.numberOfLines = 0
        detailsLabel.textAlignment = .center
        detailsLabel.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(detailsLabel)
        
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: self.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            
            detailsLabel.centerXAnchor.constraint(equalTo: self.centerXAnchor),
            detailsLabel.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
        
        // When the use-case settings change, update the actions
        collectionView.$selectedProduct
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selectedProduct in
                self?.selectedProduct = selectedProduct
            }.store(in: &cancellables)
        
        // Show the initial details and prepare the layout so that the layout will be correct
        showDetails(for: selectedProduct)
        collectionView.collectionViewLayout.prepare()
    }
    
    var products: [Database.Product] {
        get { collectionView.products }
        set { collectionView.products = newValue }
    }
    
    @Published var selectedProduct: Database.Product? {
        didSet {
            showDetails(for: selectedProduct)
        }
    }
    
    var selectedCell: CollectionView.Cell? {
        return collectionView.selectedCell
    }
    
    private func showDetails(for product: Database.Product?) {
        // Set the detail content
        let name = product?.name ?? ""
        let attributedString = NSMutableAttributedString(string: name + "\n", attributes: [
            .font: UIFont.preferredFont(forTextStyle: .title1),
            .foregroundColor: UIColor.label
        ])
        let price = product != nil ? String(format: "$%.02f", product!.price) : ""
        attributedString.append(NSAttributedString(string: price + "\n", attributes: [
            .font: UIFont.preferredFont(forTextStyle: .title2),
            .foregroundColor: UIColor.label
        ]))
        let location = product?.location ?? ""
        attributedString.append(NSAttributedString(string: location, attributes: [
            .font: UIFont.preferredFont(forTextStyle: .title3),
            .foregroundColor: UIColor.secondaryLabel
        ]))
        
        detailsLabel.attributedText = attributedString
        detailsLabel.sizeToFit()
    }

    class CollectionView: UICollectionView, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
        
        init() {
            super.init(frame: .zero, collectionViewLayout: FlowLayout())
            setup()
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setup()
        }
        
        private func setup() {
            self.register(Cell.self, forCellWithReuseIdentifier: "cell")
            self.showsHorizontalScrollIndicator = false
            self.dataSource = self
            self.delegate = self
        }
        
        var products: [Database.Product] = [] {
            didSet {
                self.reloadData()
                updateSelectedProduct()
            }
        }
        
        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            return products.count
        }
        
        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! Cell
            let product = products[indexPath.item]
            cell.imageView.image = product.image
            
            return cell
        }
        
        // MARK: - Selected Item
        
        @Published var selectedProduct: Database.Product?
        
        var selectedCell: Cell? {
            let selectedCell: Cell?
            if let selectedItemIndexPath = self.selectedItemIndexPath {
                selectedCell = cellForItem(at: selectedItemIndexPath) as? Cell
            } else {
                selectedCell = nil
            }
            
            return selectedCell
        }
        
        private var selectedItemIndexPath: IndexPath? {
            if products.count > 0 {
                let layout = collectionViewLayout as! UICollectionViewFlowLayout
                let contentOffsetX = self.contentOffset.x
                let itemWidth = layout.itemSize.width + layout.minimumLineSpacing
                let itemIndex = Int(round(contentOffsetX / itemWidth))
                let clampedItemIndex = min(max(0, itemIndex), products.count - 1)
                
                return IndexPath(item: clampedItemIndex, section: 0)
            }
            
            return nil
        }
        
        private func updateSelectedProduct() {
            if products.count == 0 {
                self.selectedProduct = nil
            } else {
                let selectedProduct: Database.Product
                if let selectedItemIndexPath = self.selectedItemIndexPath {
                    selectedProduct = products[selectedItemIndexPath.item]
                } else {
                    selectedProduct = products[0]
                }
                
                if selectedProduct != self.selectedProduct {
                    self.selectedProduct = selectedProduct
                    
                    if self.isDragging || self.isTracking {
                        generateSelectionFeedback()
                    }
                }
            }
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updateSelectedProduct()
        }
        
        // MARK: - Haptic Feedback
        
        private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()
        
        private func generateSelectionFeedback() {
            selectionFeedbackGenerator.selectionChanged()
            selectionFeedbackGenerator.prepare()
        }
        
        // MARK: - Layout
        
        private class FlowLayout: UICollectionViewFlowLayout {
            override func prepare() {
                super.prepare()
                
                let collectionView = collectionView!
                let collectionViewSize = collectionView.bounds.size
                let productsView = collectionView.superview as! ProductsView
                let detailsLabelSize = productsView.detailsLabel.frame.size
                
                let numberOfItems: Int
                if UIDevice.current.userInterfaceIdiom == .pad {
                    if collectionView.bounds.height < 500 {
                        numberOfItems = 5
                    } else {
                        numberOfItems = 4
                    }
                } else {
                    numberOfItems = 2
                }
                
                // Item width
                let itemWidth = collectionViewSize.width / CGFloat(numberOfItems)
                
                // Section inset
                let horizontalInset = (collectionViewSize.width / 2) - (itemWidth / 2)
                sectionInset = UIEdgeInsets(top: 8, left: horizontalInset, bottom: detailsLabelSize.height + 8, right: horizontalInset)
                
                // Item size
                let itemHeight = collectionViewSize.height - sectionInset.top - sectionInset.bottom
                if itemWidth > 0, itemHeight > 0 {
                    itemSize = CGSize(width: itemWidth, height: itemHeight)
                }
                
                // Scroll direction
                scrollDirection = .horizontal
                
                // Spacing
                minimumLineSpacing = 0
                minimumInteritemSpacing = 0
            }
            
            override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
                return true
            }
            
            override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint, withScrollingVelocity velocity: CGPoint) -> CGPoint {
                let itemWidth = itemSize.width + minimumLineSpacing
                let itemIndex = round(proposedContentOffset.x / itemWidth)
                let newOffsetX = itemWidth * CGFloat(itemIndex)
                return CGPoint(x: newOffsetX, y: proposedContentOffset.y)
            }
        }
        
        // MARK: - Cell
        
        class Cell: UICollectionViewCell {
            let imageView = UIImageView()
            
            override init(frame: CGRect) {
                super.init(frame: frame)
                setup()
            }
            
            required init?(coder: NSCoder) {
                super.init(coder: coder)
            }

            private func setup() {
                self.backgroundColor = .clear
                
                imageView.backgroundColor = .clear
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
                    imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                    imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                    imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
                ])
            }
        }
    }
}
