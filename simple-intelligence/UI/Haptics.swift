//
//  Haptics.swift
//  simple-intelligence
//
//  Created by Wayne Carter on 6/26/24.
//

import UIKit

class Haptics {
    static let shared = Haptics()
    
    private let selectionFeedbackGenerator = UISelectionFeedbackGenerator()
    
    private init() {
        selectionFeedbackGenerator.prepare()
    }
    
    func generateSelectionFeedback() {
        selectionFeedbackGenerator.selectionChanged()
        selectionFeedbackGenerator.prepare()
    }
}
