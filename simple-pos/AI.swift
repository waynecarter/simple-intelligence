//
//  AI.swift
//  simple-pos
//
//  Created by Wayne Carter on 5/18/24.
//

import UIKit
import Vision

struct AI {
    static let shared = AI()
    private init() {}
    
    func featureEmbedding(for image: UIImage, completion: @escaping ([NSNumber]?) -> Void) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }
        
        // Process the input image
        let processedCgImage = process(cgImage: cgImage)
        
        DispatchQueue.global().async(qos: .userInitiated) {
            featureEmbedding(for: processedCgImage, completion: completion)
        }
    }
        
    private func featureEmbedding(for cgImage: CGImage, completion: @escaping ([NSNumber]?) -> Void) {
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        let request = VNGenerateImageFeaturePrintRequest { request, error in
            guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                completion(nil)
                return
            }

            // Access the feature print data
            let data = observation.data
            guard data.isEmpty == false else {
                completion(nil)
                return
            }

            // Determine the element type and size
            let elementType = observation.elementType
            let elementCount = observation.elementCount
            let typeSize = VNElementTypeSize(elementType)
            var embedding: [NSNumber] = []
            
            // Handle the different element types
            switch elementType {
            case .float where typeSize == MemoryLayout<Float>.size:
                data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                    let buffer = bytes.bindMemory(to: Float.self)
                    if buffer.count == elementCount {
                        embedding = buffer.map { NSNumber(value: $0) }
                    }
                }
            case .double where typeSize == MemoryLayout<Double>.size:
                data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                    let buffer = bytes.bindMemory(to: Double.self)
                    if buffer.count == elementCount {
                        embedding = buffer.map { NSNumber(value: $0) }
                    }
                }
            default:
                print("Unsupported VNElementType: \(elementType)")
                completion(nil)
                return
            }

            completion(embedding)
        }

        do {
            try requestHandler.perform([request])
        } catch {
            print("Failed to perform the request: \(error.localizedDescription)")
            completion(nil)
        }
    }
    
    // MARK: - Image Processing
    
    private func process(cgImage: CGImage) -> CGImage {
        var processedImage = cropToSalientRegion(cgImage: cgImage)
        processedImage = fit(cgImage: processedImage, to: CGSize(width: 100, height: 100))
        return processedImage
    }
    
    private func cropToSalientRegion(cgImage: CGImage) -> CGImage {
        // Perform saliency detection
        let request = VNGenerateObjectnessBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return cgImage
        }

        // Get the salient objects
        guard let observation = request.results?.first as? VNSaliencyImageObservation,
              let salientObject = observation.salientObjects?.first else {
            return cgImage
        }

        // Get the bounding box of the salient region, converting the bounding box from
        // Vision normalized coordinates to CoreGraphics coordinates
        let boundingBox = salientObject.boundingBox
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        let salientRect = CGRect(
            x: boundingBox.origin.x * imageSize.width,
            y: (1 - boundingBox.origin.y - boundingBox.height) * imageSize.height,
            width: boundingBox.width * imageSize.width,
            height: boundingBox.height * imageSize.height
        )

        // Crop the image to the salient region
        guard let croppedCgImage = cgImage.cropping(to: salientRect) else {
            return cgImage
        }
        
        return croppedCgImage
    }
    
    private func fit(cgImage: CGImage, to targetSize: CGSize) -> CGImage {
        let imageSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        // Calculate the aspect ratios
        let widthRatio = targetSize.width / imageSize.width
        let heightRatio = targetSize.height / imageSize.height
        let scaleFactor = min(widthRatio, heightRatio) // Use min to fit the content without cropping

        let scaledWidth = imageSize.width * scaleFactor
        let scaledHeight = imageSize.height * scaleFactor
        let offsetX = (targetSize.width - scaledWidth) / 2.0 // Center horizontally
        let offsetY = (targetSize.height - scaledHeight) / 2.0 // Center vertically
        let scaledRect = CGRect(x: offsetX, y: offsetY, width: scaledWidth, height: scaledHeight)

        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1 // Use a scale factor of 1 for CGImage
        let rendererSize = CGSize(width: targetSize.width, height: targetSize.height)

        let renderer = UIGraphicsImageRenderer(size: rendererSize, format: rendererFormat)
        let fitImage = renderer.image { _ in
            UIImage(cgImage: cgImage).draw(in: scaledRect)
        }
        
        guard let fitImage = fitImage.cgImage else {
            return cgImage
        }
        
        return fitImage
    }
}
