//
//  PayBarButtonItem.swift
//  simple-intelligence
//
//  Created by Wayne Carter on 6/26/24.
//

import UIKit

class PayBarButtonItem: UIBarButtonItem {
    private let button = UIButton(type: .custom)
    private let font: UIFont = UIFont.preferredFont(forTextStyle: .title3)
    private let boldFont = UIFont(descriptor: UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3).withSymbolicTraits(.traitBold)!, size: 0)
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setup()
    }
    
    private func setup() {
        total = 0
        
        let buttonContainer = UIView()
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        
        button.configuration = UIButton.Configuration.filled()
        button.configuration?.buttonSize = .large
        button.configuration?.baseBackgroundColor = .systemBlue
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction(title: "Pay") { [weak self] _ in
            if let target = self?.target, let action = self?.action {
                _ = target.perform(action, with: self)
            }
        }, for: .touchUpInside)
        buttonContainer.addSubview(button)
        
        // Add padding to fit in with standard spacing
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: buttonContainer.topAnchor, constant: 2),
            button.leftAnchor.constraint(equalTo: buttonContainer.leftAnchor),
            button.rightAnchor.constraint(equalTo: buttonContainer.rightAnchor),
            button.bottomAnchor.constraint(equalTo: buttonContainer.bottomAnchor, constant: -2)
        ])
        
        self.customView = buttonContainer
    }
    
    var total: Double = .zero {
        didSet {
            var title = AttributedString("Pay", attributes: AttributeContainer([.font: boldFont, .foregroundColor: UIColor.white]))
            if total > 0 {
                title.append(AttributedString(String(format: " $%0.2f", total), attributes: AttributeContainer([.font: font, .foregroundColor: UIColor.white])))
            }
            
            button.configuration?.attributedTitle = title
            button.sizeToFit()
            self.isHidden = total <= 0
        }
    }
}
