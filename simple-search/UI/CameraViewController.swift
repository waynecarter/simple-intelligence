//
//  CamerViewController.swift
//  simple-search
//
//  Created by Wayne Carter on 6/24/24.
//

import UIKit
import AVFoundation
import Combine

class CameraViewController: ProductsViewController {
    @IBOutlet weak var explainerView: UIView!
    
    private var cancellables = Set<AnyCancellable>()
    
    private func setup() {
        view.backgroundColor = .secondarySystemBackground
        
        // Check the camera authorization and display the explainer if needed
        updateCameraAuthorization()
        
        let camera = Camera.shared
        camera.preview.frame = view.bounds
        camera.preview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        camera.preview.previewLayer.videoGravity = .resizeAspectFill
        view.insertSubview(camera.preview, at: 0)
        
        // When the products from the camera change, update the products
        Camera.shared.$products
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] products in
                self?.products = products
                if products.count > 0 {
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
        updateStyleForProducts()
    }
    
    private func updateStyleForProducts() {
        let camera = Camera.shared
        
        if products.count > 0 {
            if camera.isRunning {
                // Stop the camera
                camera.stop()
                // Hide the preview
                camera.preview.hide(animations: {
                    self.updateStyleForCamera(isRunning: false)
                })
            }
        } else {
            if camera.isRunning == false {
                // Hide the preview
                camera.preview.hide(animations: {
                    self.updateStyleForCamera(isRunning: false)
                }, completion: {
                    // Start the camera
                    camera.start {
                        // If the camera is enabled, show the preview
                        if camera.authorized {
                            DispatchQueue.main.async {
                                camera.preview.show(animations: {
                                    self.updateStyleForCamera(isRunning: true)
                                })
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
    
    // MARK: - Products
    
    override var products: [Database.Product] {
        didSet {
            // When the products change, update the styling
            guard oldValue != products else { return }
            updateStyleForProducts()
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
