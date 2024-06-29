//
//  Camera.swift
//  simple-search
//

import UIKit
import AVFoundation
import Combine

class Camera : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    static let shared = Camera()
    
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "VideoSessionQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private let captureInterval: TimeInterval = 0.2
    private var captureTimestamp: TimeInterval = 0.0
    
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator!
    private var rotationObservers = [AnyObject]()
    
    private var cancellables = Set<AnyCancellable>()
    
    @Published var authorized: Bool = false
    @Published var products: [Database.Product] = []
    let preview: Preview
    
    private override init() {
        self.preview = Preview(session: session)
        super.init()
        
        setup()
    }
    
    deinit {
        stop()
    }
    
    private func setup() {
        updateCameraAuthorization()
        
        if session.inputs.count > 0 && session.outputs.count > 0 {
            return
        }
        
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        } else {
            session.sessionPreset = .medium
        }
        
        do {
            if session.outputs.count == 0 {
                if session.canAddOutput(videoOutput) {
                    videoOutput.alwaysDiscardsLateVideoFrames = true
                    videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
                    videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
                    session.addOutput(videoOutput)
                } else {
                    throw "Could not add video output"
                }
            }
            
            if session.inputs.count == 0 {
                try updateVideoInputDevice()
            }
        } catch {
            print(error.localizedDescription)
        }
        
        Settings.shared.$frontCameraEnabled
            .sink { [weak self] frontCameraEnabled in
                self?.position = frontCameraEnabled ? .front : .back
            }.store(in: &cancellables)
    }
    
    private var position: AVCaptureDevice.Position = Settings.shared.frontCameraEnabled ? .front : .back {
        didSet {
            if position != oldValue {
                cameraPositionDidChange()
            }
        }
    }
    
    private func updateCameraAuthorization() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized: if !authorized { authorized = true }
        default: if authorized { authorized = false }
        }
    }
    
    var isRunning: Bool {
        return session.isRunning
    }
    
    func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [unowned self] granted in
                self.updateCameraAuthorization()
                if granted {
                    self.startSession()
                }
            }
        } else {
            self.updateCameraAuthorization()
            if status == .authorized {
                self.startSession()
            }
        }
    }
    
    private func startSession() {
        sessionQueue.async {
            guard self.session.isRunning == false else { return }
            self.captureTimestamp = 0
            self.session.startRunning()
        }
    }
    
    func stop() {
        sessionQueue.async {
            self.session.stopRunning()
        }
    }
    
    func updateVideoInputDevice() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        // Get the video device
        guard let device = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInDualCamera, for: .video, position: position)
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        else {
            throw "No video device found"
        }
        
        // Configure the device
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            
            if device.isSmoothAutoFocusSupported {
                device.isSmoothAutoFocusEnabled = true
            }
            
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
        } catch {
            print("Error configuring video device: \(error)")
        }
        
        var input: AVCaptureDeviceInput!
        do {
            input = try AVCaptureDeviceInput(device: device)
            if let currentInput = session.inputs.first {
                if currentInput.isEqualTo(input) { return }
                session.removeInput(currentInput)
            }
        } catch {
            throw "Could not get video input"
        }
        
        if !session.canAddInput(input) {
            throw "Could not add video input"
        }
        
        session.addInput(input)
        
        createRotationCoordinator(for: device, previewLayer: preview.previewLayer)
    }
    
    private func createRotationCoordinator(for device: AVCaptureDevice, previewLayer: AVCaptureVideoPreviewLayer) {
        // Create a new rotation coordinator for this device
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        
        // Cancel previous observations
        rotationObservers.removeAll()
        
        // Add observers to monitor future changes
        rotationObservers.append(
            rotationCoordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new, .initial]) { [weak self] _, change in
                guard let self, let angle = change.newValue else { return }
                DispatchQueue.main.async {
                    self.preview.previewLayer.connection?.videoRotationAngle = angle
                }
            }
        )
        
        rotationObservers.append(
            rotationCoordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new, .initial]) { [weak self] _, change in
                guard let self, let angle = change.newValue else { return }
                self.videoOutput.connections.forEach { $0.videoRotationAngle = angle }
            }
        )
    }
    
    private func cameraPositionDidChange() {
        sessionQueue.async {
            if self.session.inputs.count == 0 { return }
            
            do {
                try self.updateVideoInputDevice()
            } catch {
                print(error.localizedDescription)
            }
        }
    }
    
    private func imageFromSampleBuffer(sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)

        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }
    
    func shouldCaptureImage() -> Bool {
        let now = Date.now.timeIntervalSince1970
        
        if captureTimestamp == 0 {
            captureTimestamp = now
            return false
        }
        
        if now - captureTimestamp < captureInterval {
            return false
        }
        
        captureTimestamp = now
        return true
    }
  
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard shouldCaptureImage() else { return }
        
        guard let image = imageFromSampleBuffer(sampleBuffer: sampleBuffer) else {
            return
        }
        
        // Get the bounds and focus rect for
        var previewBounds: CGRect = .zero
        var focusRect: CGRect = .zero
        DispatchQueue.main.sync {
            previewBounds = preview.bounds
            focusRect = preview.focusRect
        }
        
        self.sessionQueue.async {
            guard self.session.isRunning else { return }
            
            // Find the products
            let croppedImage = self.cropImage(image, toFocusRect: focusRect, inPreviewBounds: previewBounds)
            var products = Database.shared.search(image: croppedImage)
            
            // If no products were found, try to find them in a more focused rect
            if products.count == 0 {
                let smallerFocusRect = focusRect.insetBy(dx: focusRect.width / 4, dy: focusRect.height / 4)
                let smallerCroppedImage = self.cropImage(image, toFocusRect: smallerFocusRect, inPreviewBounds: previewBounds)
                products = Database.shared.search(image: smallerCroppedImage)
            }
            
            // If the found products have changed, update them
            if self.products != products {
                self.products = products
            }
        }
    }
    
    private func cropImage(_ image: UIImage, toFocusRect focusRect: CGRect, inPreviewBounds previewBounds: CGRect) -> UIImage {
        let imageWidth = CGFloat(image.size.width)
        let imageHeight = CGFloat(image.size.height)

        // Calculate scale and offset based on videoGravity
        let scale: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
        switch preview.previewLayer.videoGravity {
        case .resizeAspectFill:
            scale = max(previewBounds.width / imageWidth, previewBounds.height / imageHeight)
            offsetX = (previewBounds.width - imageWidth * scale) / 2
            offsetY = (previewBounds.height - imageHeight * scale) / 2
        default: // .resizeAspect, .resize
            scale = min(previewBounds.width / imageWidth, previewBounds.height / imageHeight)
            offsetX = (previewBounds.width - imageWidth * scale) / 2
            offsetY = (previewBounds.height - imageHeight * scale) / 2
        }

        // Convert the focusRect from preview coordinates to image coordinates
        let focusRectInImage = CGRect(
            x: (focusRect.origin.x - offsetX) / scale,
            y: (focusRect.origin.y - offsetY) / scale,
            width: focusRect.width / scale,
            height: focusRect.height / scale
        )

        // Render the new image with the specified crop rectangle size
        let croppedImage = UIGraphicsImageRenderer(size: focusRectInImage.size).image { _ in
            // Calculate the point to start drawing the image to crop it correctly
            let drawPoint = CGPoint(x: -focusRectInImage.origin.x, y: -focusRectInImage.origin.y)
            image.draw(at: drawPoint)
        }

        return croppedImage
    }
    
    class Preview: UIView {
        private let viewfinderImageView = UIImageView()
        private var viewfinderWidthConstraint: NSLayoutConstraint?
        
        let previewLayer: AVCaptureVideoPreviewLayer
        var focusRect: CGRect { viewfinderImageView.frame }
        
        init(session: AVCaptureSession) {
            self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
            super.init(frame: .zero)
            
            setup()
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) not supported.")
        }
        
        private func setup() {
            self.backgroundColor = .systemBackground
            
            layer.addSublayer(previewLayer)
            
            viewfinderImageView.image = UIImage(systemName: "viewfinder", withConfiguration: UIImage.SymbolConfiguration(weight: .ultraLight))
            viewfinderImageView.tintColor = .white
            addSubview(viewfinderImageView)
        }
        
        private func layout() {
            // Layout preview layer
            previewLayer.frame = self.bounds
            
            // Layout viewfinder
            let viewfinderSize = 0.7 * min(self.bounds.width, self.bounds.height)
            let centeredX = (self.bounds.width - viewfinderSize) / 2
            let centeredY = (self.bounds.height - viewfinderSize) / 2
            viewfinderImageView.frame = CGRect(x: centeredX, y: centeredY, width: viewfinderSize, height: viewfinderSize)
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            layout()
        }
        
        func show(animations: (() -> Void)? = nil, completion: (() -> Void)? = nil, animated: Bool = true) {
            if animated == false {
                self.alpha = 1
                animations?()
                completion?()
                return
            }
            
            UIView.animate(withDuration: 0.2, delay: 0.5) {
                self.alpha = 1
                animations?()
            } completion: { _ in
                completion?()
            }
        }
        
        func hide(animations: (() -> Void)? = nil, completion: (() -> Void)? = nil, animated: Bool = true) {
            if animated == false {
                self.alpha = 0
                animations?()
                completion?()
                return
            }
            
            UIView.animate(withDuration: 0.2) {
                self.alpha = 0
                animations?()
            } completion: { _ in
                completion?()
            }
        }
    }
}

extension AVCaptureInput {
    func isEqualTo(_ other: AVCaptureInput) -> Bool {
        if let m = self as? AVCaptureDeviceInput, let o = other as? AVCaptureDeviceInput {
            return m.device.uniqueID == o.device.uniqueID
        }
        return false
    }
}

extension String: Error, LocalizedError {
    public var errorDescription: String? { return self }
}
