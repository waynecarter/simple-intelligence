//
//  Camera.swift
//  simple-pos
//

import UIKit
import AVFoundation
import Combine

protocol CameraDelegate {
    func camera(_ camera: Camera, didFindProducts products: [Database.Product])
    func camera(_ camera: Camera, didFailWithError error: Error)
}

class Camera : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private lazy var database = { return Database.shared }()
    private lazy var ai = { return AI.shared }()
    
    private let session: AVCaptureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "VideoSessionQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private let captureInterval: TimeInterval = 0.2
    private var captureTimestamp: TimeInterval = 0.0
    
    private var kioskMode = Settings.shared.kioskModeEnabled
    
    private var position: AVCaptureDevice.Position = Settings.shared.frontCameraEnabled ? .front : .back {
        didSet {
            if position != oldValue {
                cameraPositionDidChange()
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private var lastProducts: [Database.Product]?
    
    private var delegate: CameraDelegate
    
    init(delegate: CameraDelegate) {
        self.delegate = delegate
        
        super.init()
        
        Settings.shared.$frontCameraEnabled
            .sink { [weak self] frontCameraEnabled in
                self?.position = frontCameraEnabled ? .front : .back
            }.store(in: &cancellables)
        
        Settings.shared.$kioskModeEnabled
            .sink { [weak self] kioskMode in
                self?.sessionQueue.async {
                    self?.kioskMode = kioskMode
                }
            }.store(in: &cancellables)
    }
    
    deinit {
        stop()
    }
    
    func start() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [unowned self] granted in
                self.startSession()
            }
        } else {
            self.startSession()
        }
    }
    
    private func startSession() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status != .authorized {
            self.delegate.camera(self, didFailWithError: "No permission to use the camera device")
            return
        }
        
        sessionQueue.async {
            if self.session.isRunning { return }
            
            do {
                try self.setup()
            } catch {
                self.delegate.camera(self, didFailWithError: error)
                return
            }
            
            self.captureTimestamp = 0
            self.session.startRunning()
            
            if (!self.session.isRunning) {
                self.delegate.camera(self, didFailWithError: "Camera cannot start")
            }
        }
    }
    
    func stop() {
        sessionQueue.async {
            self.session.stopRunning()
        }
    }
    
    private func setup() throws {
        if session.inputs.count > 0 && session.outputs.count > 0 {
            return
        }
        
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }
        
        session.sessionPreset = .vga640x480
        
        if session.inputs.count == 0 {
            try updateVideoInputDevice()
        }
        
        if session.outputs.count == 0 {
            if session.canAddOutput(videoOutput) {
                videoOutput.alwaysDiscardsLateVideoFrames = true
                videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
                videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
                session.addOutput(videoOutput)
                updateVideoOutputAngle()
            } else {
                throw "Could not add video output"
            }
        }
    }
    
    func updateVideoInputDevice() throws {
        session.beginConfiguration()
        defer {
            session.commitConfiguration()
        }
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw "No video device found"
        }
        
        var input: AVCaptureDeviceInput!
        do {
            input = try AVCaptureDeviceInput(device: device)
            if let currentInput = session.inputs.first {
                if (currentInput.isEqualTo(input)) {
                    return
                }
                session.removeInput(currentInput)
            }
        } catch {
            throw "Could not get video input"
        }
        
        if !session.canAddInput(input) {
            throw "Could not add video input"
        }
        session.addInput(input)
        
        updateVideoOutputAngle()
    }
    
    private func updateVideoOutputAngle() {
        if session.outputs.count == 0 { return }
        
        let connection = videoOutput.connection(with: .video)!
        if (UIDevice.current.userInterfaceIdiom == .pad) {
            connection.videoRotationAngle = position == .front ? 0 : 180
        } else {
            connection.videoRotationAngle = 90
        }
    }
    
    private func cameraPositionDidChange() {
        sessionQueue.async {
            if self.session.inputs.count == 0 { return }
            
            do {
                try self.updateVideoInputDevice()
            } catch {
                self.delegate.camera(self, didFailWithError: error)
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
        if !shouldCaptureImage() { return }
        
        guard let image = imageFromSampleBuffer(sampleBuffer: sampleBuffer) else {
            return
        }
        
        self.ai.featureEmbedding(for: image) { embedding in
            guard let embedding = embedding else { return }
            
            self.sessionQueue.async {
                if !self.session.isRunning { return }
                
                let products = self.database.search(vector: embedding)
                
                if products.isEmpty {
                    self.lastProducts = nil
                    return
                }
                
                if self.kioskMode {
                    if let lastProducts = self.lastProducts, lastProducts == products {
                        return
                    }
                }
                
                self.lastProducts = products
                
                self.session.stopRunning()
                
                self.delegate.camera(self, didFindProducts: products)
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
