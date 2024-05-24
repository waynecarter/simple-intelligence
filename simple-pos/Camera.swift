//
//  Camera.swift
//  simple-pos
//

import UIKit
import AVFoundation
import Combine

protocol CameraDelegate {
    func camera(_ camera: Camera, didCaptureImage image: UIImage)
    func camera(_ camera: Camera, didFailWithError error: Error)
}

class Camera : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session: AVCaptureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "VideoSessionQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private let captureInterval: TimeInterval = 0.2
    private var captureTimestamp: TimeInterval = 0.0
    
    private var delegate: CameraDelegate?
    
    private var position: AVCaptureDevice.Position = Settings.shared.frontCameraEnabled ? .front : .back
    private var cancellables = Set<AnyCancellable>()
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    var isRunning: Bool { session.isRunning }
    
    init(delegate: CameraDelegate) {
        super.init()
        self.delegate = delegate
        Settings.shared.$frontCameraEnabled
            .dropFirst()
            .sink { [weak self] frontCameraEnabled in
                guard let self = self else { return }
                do {
                    try self.setVideoInputDevice(position: frontCameraEnabled ? .front : .back)
                } catch {
                    self.delegate?.camera(self, didFailWithError: error)
                }
            }.store(in: &cancellables)
    }
    
    deinit {
        stop()
    }
    
    func start(_ completion: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [unowned self] granted in
                self.startSession(completion)
            }
        } else {
            self.startSession(completion)
        }
    }
    
    private func startSession(_ completion: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        if self.session.isRunning {
            completion(true, nil)
            return
        }
        
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status != .authorized {
            completion(false, "No permission to use the camera device")
            return
        }
        
        do {
            try self.setup()
        } catch {
            completion(false, error)
            return
        }
        
        sessionQueue.async {
            self.captureTimestamp = 0
            self.session.startRunning()
            completion(self.session.isRunning, self.session.isRunning ? nil : "Camera cannot start")
        }
    }
    
    func stop(_ completion: (() -> Void)? = nil) {
        sessionQueue.async {
            self.session.stopRunning()
            
            if let completion = completion {
                completion()
            }
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
            try setVideoInputDevice(position: position)
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
        
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer!.videoGravity = AVLayerVideoGravity.resizeAspectFill
    }
    
    func setVideoInputDevice(position: AVCaptureDevice.Position) throws {
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
            throw "Could not use video input"
        }
        
        guard session.canAddInput(input) else {
            throw "Could not add video input"
        }
        session.addInput(input)
        
        updateVideoOutputAngle()
        
        self.position = position
    }
    
    private func updateVideoOutputAngle() {
        if session.outputs.count > 0 {
            let connection = videoOutput.connection(with: .video)!
            if (UIDevice.current.userInterfaceIdiom == .pad) {
                connection.videoRotationAngle = Settings.shared.frontCameraEnabled ? 0.0 : 180.0
            } else {
                connection.videoRotationAngle = 90.0
            }
            connection.isVideoMirrored = Settings.shared.frontCameraEnabled
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

        if let delegate = self.delegate {
            delegate.camera(self, didCaptureImage: image)
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
