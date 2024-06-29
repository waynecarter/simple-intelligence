//
//  PayBarButtonItem.swift
//  simple-search
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
        
        button.configuration = UIButton.Configuration.filled()
        button.configuration?.buttonSize = .large
        button.configuration?.baseBackgroundColor = .systemBlue
        button.addAction(UIAction(title: "Pay") { [weak self] _ in
            if let target = self?.target, let action = self?.action {
                _ = target.perform(action, with: self)
            }
        }, for: .touchUpInside)
        
        self.customView = button
    }
    
    var total: Double = .zero {
        didSet {
            var title = AttributedString()
            title.append(AttributedString("Pay", attributes: AttributeContainer([.font: boldFont, .foregroundColor: UIColor.white])))

            if total > 0 {
                title.append(AttributedString(String(format: " $%0.2f", total), attributes: AttributeContainer([.font: font, .foregroundColor: UIColor.white])))
            }
            
            button.configuration?.attributedTitle = title
            button.sizeToFit()
            self.isHidden = total <= 0
        }
    }
}
