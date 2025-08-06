/*
See the License.txt file for this sample's licensing information.
*/

import AVFoundation
import SwiftUI
import os.log
import CoreImage
import Combine

enum CameraMode {
    case preview
    case captured(UIImage)
    case textRecognition(UIImage)
}

final class DataModel: ObservableObject {
    let camera = Camera()
    let effectsPipeline = EffectsPipeline()
    
    @Published var cameraMode: CameraMode = .preview
    
    // Store only UIImage data, not SwiftUI Image views
    @Published var capturedUIImage: UIImage?
    @Published var processedUIImage: UIImage?
    
    // Keep this for text recognition mode
    var lastCapturedUIImage: UIImage? {
        capturedUIImage
    }
    
    init() {
        Task {
            await handleCameraPhotos()
        }
    }
    
    func resetCamera() {
        // Reset all captured images
        capturedUIImage = nil
        processedUIImage = nil
        
        // Reset camera mode to preview
        cameraMode = .preview
        
        // Reset effects pipeline
        effectsPipeline.subjectPosition = nil
        effectsPipeline.inputImage = nil
        
        // Clear any cached masks or outlines
        effectsPipeline.maskPreview = nil
        effectsPipeline.outlinePath = nil
        effectsPipeline.cutoutImage = nil
    }
    
    func enterTextRecognitionMode() {
        if let uiImage = capturedUIImage {
            cameraMode = .textRecognition(uiImage)
        }
    }
    
    func handleCameraPhotos() async {
        let unpackedPhotoStream = camera.photoStream
            .compactMap { self.unpackPhoto($0) }
        
        for await (originalUIImage, processedUIImage) in unpackedPhotoStream {
            Task { @MainActor in
                self.capturedUIImage = originalUIImage
                self.processedUIImage = processedUIImage
                self.cameraMode = .captured(originalUIImage)
            }
        }
    }
    
    private func unpackPhoto(_ uiImage: UIImage) -> (UIImage, UIImage)? {
        // Fix orientation if needed
        let oriented = uiImage.fixedOrientation()
        
        // Process for bokeh effect
        let processedUIImage: UIImage
        if let ci = CIImage(image: oriented) {
            effectsPipeline.inputImage = ci
            processedUIImage = effectsPipeline.processImageSync(ci)
        } else {
            processedUIImage = oriented
        }
        
        // Return only UIImage data
        return (oriented, processedUIImage)
    }
}

fileprivate extension UIImage {
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalizedImage ?? self
    }
}

fileprivate let logger = Logger(subsystem: "com.apple.swiftplaygroundscontent.capturingphotos", category: "DataModel")
