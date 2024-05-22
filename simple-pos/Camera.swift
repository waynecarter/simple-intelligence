//
//  Camera.swift
//  simple-pos
//

import UIKit
import AVFoundation

protocol CameraDelegate {
    func didCaptureImage(_ image: UIImage)
}

class Camera : NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let session: AVCaptureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "VideoSessionQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private let captureInterval: TimeInterval = 0.2
    private var captureTimestamp: TimeInterval = 0.0
    
    private var delegate: CameraDelegate?
    
    private var position: AVCaptureDevice.Position = UIDevice.current.userInterfaceIdiom == .phone ? .back : .back
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    var isRunning: Bool { session.isRunning }
    
    init(delegate: CameraDelegate) {
        self.delegate = delegate
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
            completion(false, "No permission to use the video device")
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
            completion(self.session.isRunning, self.session.isRunning ? nil : "Video capture session cannot start")
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
            if session.canAddOutput(videoDataOutput) {
                videoDataOutput.alwaysDiscardsLateVideoFrames = true
                videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
                videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
                session.addOutput(videoDataOutput)
                
                let captureConnection = videoDataOutput.connection(with: .video)! // Need to add first
                captureConnection.isEnabled = true
                captureConnection.videoRotationAngle = 90
            } else {
                throw "Could not add video output to the capture session"
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
            throw "Could not add video input to the capture session"
        }
        session.addInput(input)
        
        self.position = position
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
            delegate.didCaptureImage(image)
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
