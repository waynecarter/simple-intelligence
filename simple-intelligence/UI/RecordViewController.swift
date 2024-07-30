//
//  RecordViewController.swift
//  simple-intelligence
//
//  Created by Wayne Carter on 7/28/24.
//

import UIKit
import Combine

class RecordViewController: UIViewController {
    private let explainerLabel = UILabel()
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let detailsLabel = UILabel()
    private let stackView = UIStackView()
    
    var record: Database.Record? {
        didSet {
            updateUI()
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
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
        
        // Add central title label to the main view
        explainerLabel.translatesAutoresizingMaskIntoConstraints = false
        explainerLabel.textAlignment = .center
        explainerLabel.font = UIFont.preferredFont(forTextStyle: .largeTitle)
        view.addSubview(explainerLabel)
        
        // Configure stack view constraints
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stackView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stackView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            
            // Central title label constraints
            explainerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            explainerLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
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
        
        // When the use case changes, update the database the UI
        Settings.shared.$useCase
            .dropFirst()
            .sink { [weak self] useCase in
                self?.updateUI(useCase: useCase)
            }.store(in: &cancellables)
    }
    
    private func updateUI(useCase: Settings.UseCase = Settings.shared.useCase) {
        if let record = record {
            imageView.image = record.image
            titleLabel.text = record.title
            subtitleLabel.text = record.subtitle
            detailsLabel.text = record.details
            explainerLabel.isHidden = true
        } else {
            imageView.image = nil
            titleLabel.text = nil
            subtitleLabel.text = nil
            detailsLabel.text = nil
            
            switch useCase {
            case .itemLookup:
                explainerLabel.text = "Item Info"
            case .pointOfSale:
                explainerLabel.text = "Point of Sale"
            case .bookingLookup:
                explainerLabel.text = "Booking Info"
            }
            explainerLabel.isHidden = false
        }
        
        stackView.setNeedsLayout()
        stackView.layoutIfNeeded()
        adjustLabelFontSizes()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        adjustLabelFontSizes()
    }
    
    private func adjustLabelFontSizes() {
        // Calculate the total desired height for the labels (20% of the view's height)
        let totalHeight = view.frame.height
        let desiredLabelHeight = totalHeight * 0.20
        
        // Set the explainer label font size
        let explainerFontSize = desiredLabelHeight
        explainerLabel.font = UIFont.systemFont(ofSize: explainerFontSize)
        
        // Get the initial font sizes for each label
        let initialTitleFontSize = titleLabel.font.pointSize
        let initialSubtitleFontSize = subtitleLabel.font.pointSize
        let initialDetailsFontSize = detailsLabel.font.pointSize
        
        // Measure the combined height of the labels using placeholder text
        let titleHeight = " ".size(withAttributes: [.font: titleLabel.font!]).height
        let subtitleHeight = " ".size(withAttributes: [.font: subtitleLabel.font!]).height
        let detailsHeight = " ".size(withAttributes: [.font: detailsLabel.font!]).height
        let combinedHeight = titleHeight + subtitleHeight + detailsHeight
        
        // Calculate the scaling factor for title, subtitle, and details labels
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
