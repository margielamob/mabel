@preconcurrency import Vision
import UIKit
import NaturalLanguage
import CoreGraphics

/// Represents a detected text block with its content and location
struct DetectedTextBlock {
    let id = UUID()
    let text: String
    let boundingBox: CGRect // Normalized coordinates (0-1)
    let confidence: Float
    
    /// Convert normalized bounding box to view coordinates
    func viewRect(in size: CGSize) -> CGRect {
        // Vision uses bottom-left origin, UIKit uses top-left
        // Flip Y coordinate and scale to view size
        return CGRect(
            x: boundingBox.minX * size.width,
            y: (1 - boundingBox.maxY) * size.height,
            width: boundingBox.width * size.width,
            height: boundingBox.height * size.height
        )
    }
}

/// Service for performing text recognition on images
class TextRecognitionService {
    
    func recognizeText(
            in image: UIImage,
            preferredLanguages: [String]? = nil
        ) async throws -> [DetectedTextBlock] {

            guard image.cgImage != nil else { throw TextRecognitionError.invalidImage }

            // Down-sample immediately to cut peak RAM.
            let cg = image.preparingForVision(maxDimension: 2_048)

            // Run Vision on a background cooperative thread.
            let observations: [VNRecognizedTextObservation] = try await Task
                .detached(priority: .userInitiated) { [preferredLanguages] in

                    // ⚠️ Everything inside the closure is *local*,
                    // so nothing non-Sendable is captured.

                    // 1️⃣  Build request
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel           = .accurate
                    request.usesLanguageCorrection     = true
                    request.revision                   = VNRecognizeTextRequest.currentRevision
                    request.preferBackgroundProcessing = true

                    // 2️⃣  Language handling — uses **instance** API (non-deprecated)
                    if let langs = preferredLanguages, !langs.isEmpty {
                        let supported = try request.supportedRecognitionLanguages()
                        let valid     = langs.filter { supported.contains($0) }
                        request.recognitionLanguages      = valid
                        request.automaticallyDetectsLanguage = valid.isEmpty
                    } else {
                        request.automaticallyDetectsLanguage = true
                    }

                    // 3️⃣  Handler & perform
                    let handler = VNImageRequestHandler(cgImage: cg,
                                                        orientation: .up)
                    try handler.perform([request])

                    // 4️⃣  Return Vision output
                    return request.results ?? []
                }
                .value                              // ← await result here

            // Map Vision observations to your model *outside* the Task,
            // so `self` is not captured in the detached closure.
            return groupTextObservations(observations)
        }
    
    /// Groups line-level observations into larger text blocks
    private func groupTextObservations(
        _ observations: [VNRecognizedTextObservation]
    ) -> [DetectedTextBlock] {

        guard !observations.isEmpty else { return [] }

        // O(n log n)
        let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }

        var blocks: [DetectedTextBlock] = []
        var current: [VNRecognizedTextObservation] = [sorted[0]]

        for obs in sorted.dropFirst() {
            guard let last = current.last else { continue }

            let verticalDist = abs(last.boundingBox.midY - obs.boundingBox.midY)
            let threshold    = max(last.boundingBox.height, obs.boundingBox.height) * 0.8

            let horizontalOverlap =
                last.boundingBox.minX < obs.boundingBox.maxX &&
                last.boundingBox.maxX > obs.boundingBox.minX

            if verticalDist < threshold && horizontalOverlap {
                current.append(obs)
            } else {
                blocks.append(makeBlock(from: current))
                current = [obs]
            }
        }

        if !current.isEmpty { blocks.append(makeBlock(from: current)) }
        return blocks
    }

    private func makeBlock(from group: [VNRecognizedTextObservation]) -> DetectedTextBlock {
        let candidates     = group.compactMap { $0.topCandidates(1).first }
        let combinedText   = candidates.map(\.string).joined(separator: "\n")
        let boundingUnion = group.map(\.boundingBox)
                                 .reduce(into: CGRect.null) { partial, rect in
                                     partial = partial.union(rect)
                                 }
        let minConfidence  = candidates.map(\.confidence).min() ?? 0

        return DetectedTextBlock(text: combinedText,
                                 boundingBox: boundingUnion,
                                 confidence: minConfidence)
    }

    
    /// Detects the language of a text string
    func detectLanguage(for text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        
        if let language = recognizer.dominantLanguage {
            return language.rawValue
        }
        
        return nil
    }
    
    /// Creates a cropped image from the selected text region
    func cropImage(_ image: UIImage, to normalizedRect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        // Convert normalized rect to pixel coordinates
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        // Vision uses bottom-left origin, Core Graphics uses top-left
        let pixelRect = CGRect(
            x: normalizedRect.minX * imageWidth,
            y: (1 - normalizedRect.maxY) * imageHeight,
            width: normalizedRect.width * imageWidth,
            height: normalizedRect.height * imageHeight
        )
        
        // Add some padding
        let padding: CGFloat = 20
        let paddedRect = pixelRect.insetBy(dx: -padding, dy: -padding)
            .intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        
        guard let croppedCGImage = cgImage.cropping(to: paddedRect) else { return nil }
        
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}

// MARK: - Error Types
enum TextRecognitionError: LocalizedError {
    case invalidImage
    case noTextFound
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not process the image"
        case .noTextFound:
            return "No text found in the image"
        }
    }
}

// MARK: - UIImage Extension for Orientation
extension CGImagePropertyOrientation {
    init(_ uiOrientation: UIImage.Orientation) {
        switch uiOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

extension UIImage {
    func preparingForVision(maxDimension: CGFloat) -> CGImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1           // vision works in pixels
        let ratio = max(size.width, size.height) / maxDimension
        let newSize = CGSize(width: size.width / ratio, height: size.height / ratio)

        return UIGraphicsImageRenderer(size: newSize, format: format)
            .image { _ in self.draw(in: CGRect(origin: .zero, size: newSize)) }
            .cgImage!
    }
}

