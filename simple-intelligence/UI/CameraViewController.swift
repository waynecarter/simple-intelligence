//
//  CamerViewController.swift
//  simple-intelligence
//
//  Created by Wayne Carter on 6/24/24.
//

import UIKit
import AVFoundation
import Combine

class CameraViewController: RecordsViewController {
    @IBOutlet weak var explainerView: UIView!
    
    private var cancellables = Set<AnyCancellable>()
    
    private func setup() {
        // Check the camera authorization and display the explainer if needed
        updateCameraAuthorization()
        
        let camera = Camera.shared
        camera.preview.frame = view.bounds
        camera.preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        camera.preview.previewLayer.videoGravity = .resizeAspectFill
        view.insertSubview(camera.preview, at: 0)
        
        // When the records from the camera change, update the records
        Camera.shared.$records
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] records in
                self?.records = records
                if records.count > 0 {
                    Haptics.shared.generateSelectionFeedback()
                }
            }.store(in: &cancellables)
        
        Camera.shared.$authorized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authorized in
                self?.updateCameraAuthorization(authorized)
            }.store(in: &cancellables)
    }
    
    private func style() {
        tabBarController?.overrideUserInterfaceStyle = .dark
        updateStyleForRecords()
    }
    
    private func updateStyleForRecords() {
        let camera = Camera.shared
        let isShowingRecords = records.count > 0
        
        if isShowingRecords {
            // Stop the camera
            if camera.isRunning {
                camera.stop()
                // Hide the preview
                camera.preview.hide(animations: {
                    // Style the view for the records to be showing
                    self.view.backgroundColor = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1)
                    self.updateStyleForCamera(isRunning: false)
                })
            }
        } else {
            // Start the camera
            if !camera.isRunning {
                // Hide the preview
                camera.preview.hide(animations: {
                    // Style the view for the camera to be showing
                    self.view.backgroundColor = .black
                    self.updateStyleForCamera(isRunning: true)
                }, completion: {
                    // Then, start the camera
                    camera.start { started in
                        // Finally, if the camera was started successfully, show the preview
                        if started {
                            DispatchQueue.main.async {
                                camera.preview.show()
                            }
                        }
                    }
                })
            }
        }
    }
    
    func updateStyleForCamera(isRunning: Bool) {
        if isRunning {
            tabBarController?.tabBar.backgroundColor = .black.withAlphaComponent(0.7)
        } else {
            tabBarController?.tabBar.backgroundColor = nil
        }
    }
    
    private func updateCameraAuthorization(_ authorized: Bool? = nil) {
        let camera = Camera.shared
        let authorized = authorized ?? camera.authorized
        
        // If the camera is not enabled, show the explainer and hide the camera
        if authorized {
            // Show camera and hide explainer
            self.explainerView.alpha = 0
            camera.preview.show(animated: false)
        } else {
            // Show explainer and hide camera
            self.explainerView.alpha = 1
            camera.preview.hide(animated: false)
        }
    }
    
    // MARK: - Records
    
    override var records: [Database.Record] {
        didSet {
            // When the records change, update the styling
            guard oldValue != records else { return }
            updateStyleForRecords()
        }
    }
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        style()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // Stop the camera
        Camera.shared.stop()
        Camera.shared.preview.hide(animated: false)
        updateStyleForCamera(isRunning: false)
    }
}
