//
//  ViewController2.swift
//  simple-pos
//
//  Created by Wayne Carter on 5/18/24.
//

import UIKit

// Pasin, to run this view contorller, go to the SceneDelegate file
// and follow the instructions there to enable it.

class NavigationController: UINavigationController {
    
    override var prefersStatusBarHidden: Bool {
        // Present full screen without the top status bars.
        return true
    }
    
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation {
        return .slide
    }
}

class ViewController2: UICollectionViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layout()
    }
    
    private func setup() {
        if let payItem = navigationItem.rightBarButtonItem as? PayBarButtonItem {
            payItem.setTotal("$30.50")
        }
    }
    
    private func layout() {
        // Layout the "Add to Cart" bottom toolbar item to take up the full width of the screen.
        if let addToCartItem = toolbarItems?[1] {
            let horizontalPadding = view.safeAreaInsets.left + view.safeAreaInsets.right + view.layoutMargins.left + view.layoutMargins.right
            addToCartItem.width = view.bounds.width - horizontalPadding
        }
    }
    
    @IBAction func search(_ sender: Any) {
        print("Search button tapped")
    }
    
    @IBAction func addToCart(_ sender: Any) {
        print("Add to Cart button tapped")
    }
    
    @IBAction func pay(_ sender: Any) {
        print("Pay button tapped")
    }
}

class LargeToolbar: UIToolbar {
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        // Set the toolbar height to be larger than normal.
        var newSize = super.sizeThatFits(size)
        newSize.height = max(newSize.height, 80)
        return newSize
    }
}

class SearchBarButtonItem: UIBarButtonItem {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    private func setup() {
        let button = UIButton(type: .custom)
        button.configuration = UIButton.Configuration.plain()
        button.configuration?.image = UIImage(systemName: "magnifyingglass")?.withConfiguration(UIImage.SymbolConfiguration(pointSize: 24))
        button.tintColor = .label
        button.addAction(UIAction(title: "Open Search") { [weak self] _ in
            self?.touchUpInside()
        }, for: .touchUpInside)
        
        self.customView = button
    }
    
    func touchUpInside() {
        if let target = target, let action = action {
            _ = target.perform(action, with: self)
        }
    }
}

class PayBarButtonItem: UIBarButtonItem {
    private let button = UIButton(type: .custom)
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    private func setup() {
        button.configuration = UIButton.Configuration.filled()
        button.configuration?.buttonSize = .large
        button.addAction(UIAction(title: "Pay") { [weak self] _ in
            self?.touchUpInside()
        }, for: .touchUpInside)
        setTotal(nil)
        
        button.configuration?.buttonSize = .large
        
        self.customView = button
    }
    
    func setTotal(_ total: String?) {
        var title = AttributedString()
        title.append(AttributedString("Pay", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: UIFont.buttonFontSize, weight: .bold)])))
        if let total = total {
            title.append(AttributedString(" \(total)", attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: UIFont.buttonFontSize)])))
        }
        
        // Set the button title and resize to fit the new content.
        button.configuration?.attributedTitle = title
        button.sizeToFit()
    }
    
    func touchUpInside() {
        if let target = target, let action = action {
            _ = target.perform(action, with: self)
        }
    }
}

class AddToCartBarButtonItem: UIBarButtonItem {
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    private func setup() {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.configuration = {
            var config = UIButton.Configuration.filled()
            config.buttonSize = .large
            config.title = self.title
            return config
        }()
        button.addAction(UIAction(title: "Add to Bag") { [weak self] _ in
            self?.touchUpInside()
        }, for: .touchUpInside)
        
        self.customView = button
        
        // Set contraits so that when the this bar item is resized the
        // button will also resize.
        if let customView = self.customView {
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: customView.topAnchor),
                button.bottomAnchor.constraint(equalTo: customView.bottomAnchor),
                button.leadingAnchor.constraint(equalTo: customView.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: customView.trailingAnchor)
            ])
        }
    }
    
    func touchUpInside() {
        if let target = target, let action = action {
            _ = target.perform(action, with: self)
        }
    }
}
