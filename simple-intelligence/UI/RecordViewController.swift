//
//  RecordViewController.swift
//  simple-intelligence
//
//  Created by Wayne Carter on 7/28/24.
//

import UIKit

class RecordViewController: UIViewController {
    var record: Database.Record? {
        didSet {
            updateUI()
        }
    }
    
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailsLabel = UILabel()
    private let stackView = UIStackView()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    private func setup() {
        // Configure stack view
        stackView.axis = .vertical
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add subviews to stack view
        stackView.addArrangedSubview(imageView)
        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(subtitleLabel)
        stackView.addArrangedSubview(detailsLabel)
        
        // Add stack view to the main view
        view.addSubview(stackView)
        
        // Configure stack view constraints
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
        
        // Configure image view content mode
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .clear
        imageView.layer.shadowColor = UIColor.black.cgColor
        imageView.layer.shadowOffset = CGSize(width: 0, height: 18)
        imageView.layer.shadowOpacity = 0.5
        imageView.layer.shadowRadius = 36
        imageView.layer.masksToBounds = false
        
        // Configure label properties
        titleLabel.numberOfLines = 1
        titleLabel.textAlignment = .center
        titleLabel.textColor = .label
        titleLabel.font = UIFont.preferredFont(forTextStyle: .title1)
        
        subtitleLabel.numberOfLines = 1
        subtitleLabel.textAlignment = .center
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .title2)
        
        detailsLabel.numberOfLines = 1
        detailsLabel.textAlignment = .center
        detailsLabel.textColor = .secondaryLabel
        detailsLabel.font = UIFont.preferredFont(forTextStyle: .title3)
        
        // Set the labels' priority for vertical content hugging and compression resistance
        titleLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        subtitleLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        detailsLabel.setContentHuggingPriority(.defaultHigh, for: .vertical)
        
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        subtitleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        detailsLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        
        adjustLabelFontSizes()
    }
    
    private func updateUI() {
        imageView.image = record?.image
        titleLabel.text = record?.title
        subtitleLabel.text = record?.subtitle
        detailsLabel.text = record?.details
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        adjustLabelFontSizes()
    }
    
    private func adjustLabelFontSizes() {
        // Calculate the total desired height for the labels (20% of the view's height)
        let totalHeight = view.frame.height
        let desiredLabelHeight = totalHeight * 0.20
        
        // Get the initial font sizes for each label
        let initialTitleFontSize = titleLabel.font.pointSize
        let initialSubtitleFontSize = subtitleLabel.font.pointSize
        let initialDetailsFontSize = detailsLabel.font.pointSize
        
        // Measure the combined height of the labels using placeholder text
        let titleHeight = " ".size(withAttributes: [.font: titleLabel.font!]).height
        let subtitleHeight = " ".size(withAttributes: [.font: subtitleLabel.font!]).height
        let detailsHeight = " ".size(withAttributes: [.font: detailsLabel.font!]).height
        let combinedHeight = titleHeight + subtitleHeight + detailsHeight
        
        // Calculate the scaling factor
        let scalingFactor = desiredLabelHeight / combinedHeight
        
        // Adjust font sizes using individual starting font sizes
        titleLabel.font = UIFont.systemFont(ofSize: initialTitleFontSize * scalingFactor)
        subtitleLabel.font = UIFont.systemFont(ofSize: initialSubtitleFontSize * scalingFactor)
        detailsLabel.font = UIFont.systemFont(ofSize: initialDetailsFontSize * scalingFactor)
    }
    
    // MARK: - Full Screen
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
}

