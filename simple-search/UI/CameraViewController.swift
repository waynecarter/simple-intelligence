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
    @IBOutlet weak var blurEffectView: UIVisualEffectView!
    @IBOutlet weak var explainerView: UIView!
    
    private let camera: Camera = .shared
    
    private let tabBarBackgroundColor = UIColor.systemBackground.withAlphaComponent(0.7)
    
    private var cancellables = Set<AnyCancellable>()
    
    private func setup() {
        // Check the camera authorization and display the explainer if neede
        updateCameraAuthorization()
        
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
                    self?.camera.stop()
                    Haptics.shared.generateSelectionFeedback()
                }
            }.store(in: &cancellables)
        
        Camera.shared.$authorized
            .receive(on: DispatchQueue.main)
            .sink { [weak self] authorized in
                self?.updateCameraAuthorization(authorized)
            }.store(in: &cancellables)
        
        camera.start()
    }
    
    private func style() {
        tabBarController?.overrideUserInterfaceStyle = .dark
        
        if blurEffectView.alpha == 0 {
            tabBarController?.tabBar.backgroundColor = tabBarBackgroundColor
        }
    }
    
    private func updateCameraAuthorization(_ authorized: Bool? = nil) {
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
            guard oldValue != products else { return }
            
            if products.count > 0 {
                UIView.animate(withDuration: 0.2) {
                    self.blurEffectView.alpha = 1
                    self.tabBarController?.tabBar.backgroundColor = .clear
                }
            } else {
                camera.preview.hide(completion: {
                    self.camera.start()
                    self.camera.preview.show(animations: {
                        self.blurEffectView.alpha = 0
                        self.tabBarController?.tabBar.backgroundColor = self.tabBarBackgroundColor
                    })
                })
            }
        }
    }
    
    // MARK: - View Lifecycle
    
    private var cameraWasRunning = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setup()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Apply styles
        style()
        
        // If the camera was running when the view disappeared, start it again
        if cameraWasRunning {
            camera.start()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // If the camera is enabled, show it
        if camera.authorized {
            camera.preview.show()
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // If the camera is running, stop it and note whether it was running so we can restart it when the view re-appears
        cameraWasRunning = camera.isRunning
        if camera.isRunning {
            camera.stop()
            camera.preview.hide()
        }
    }
}
