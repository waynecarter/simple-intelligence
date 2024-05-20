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
    private var session: AVCaptureSession? = nil
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "VideoSessionQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private let captureInterval: TimeInterval = 1.0
    private var captureTimestamp: TimeInterval = 0.0
    
    private var delegate: CameraDelegate?
    
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    var isRunning: Bool { ((self.session?.isRunning) != nil) }
    
    init(delegate: CameraDelegate) {
        super.init()
        self.delegate = delegate
    }
    
    func start(_ completion: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [unowned self] granted in
                self.startSession(completion)
            }
            return
        }
        self.startSession(completion)
    }
    
    private func startSession(_ completion: @escaping (_ success: Bool, _ error: Error?) -> Void) {
        sessionQueue.async {
            if let session = self.session, session.isRunning {
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
            
            self.captureTimestamp = 0
            self.session!.startRunning()
            completion(self.session!.isRunning, self.session!.isRunning ? nil : "Video capture session cannot start")
        }
    }
    
    func stop(_ completion: (() -> Void)? = nil) {
        sessionQueue.async {
            if let session = self.session, session.isRunning {
                session.stopRunning()
                if let completion = completion {
                    completion()
                }
            }
        }
    }
    
    private func setup() throws {
        if session != nil {
            return
        }

        // Select a video device, make an input
        guard let videoDevice = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera],
                                                                 mediaType: .video, position: .back).devices.first else {
            throw "No video device found"
        }
        
        var deviceInput: AVCaptureDeviceInput!
        do {
            deviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            throw "Could not use video input"
        }
        
        self.session = AVCaptureSession()
        guard let session = self.session else {
            throw "Could create a capture session"
        }
        
        session.beginConfiguration()
        
        session.sessionPreset = .vga640x480 // Model image size is smaller.
        
        // Add a video input
        guard session.canAddInput(deviceInput) else {
            session.commitConfiguration()
            self.session = nil
            throw "Could not add video input to the capture session"
        }
        session.addInput(deviceInput)
        
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        } else {
            session.commitConfiguration()
            self.session = nil
            throw "Could not add video output to the capture session"
        }
        
        let captureConnection = videoDataOutput.connection(with: .video)!
        captureConnection.isEnabled = true
        captureConnection.videoRotationAngle = 90 // TODO adjust based on the device orientation
        session.commitConfiguration()
        
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer!.videoGravity = AVLayerVideoGravity.resizeAspectFill
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

extension String: Error, LocalizedError {
    public var errorDescription: String? { return self }
}
