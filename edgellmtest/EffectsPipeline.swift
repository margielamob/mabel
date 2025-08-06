/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Handles subject lifting and bokeh effect application.
*/

import Foundation
import Combine
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

/// A class that produces and publishes the postprocessed output with bokeh effect applied to subjects.
final class EffectsPipeline: ObservableObject {

    /// The source image for the effects pipeline.
    @Published var inputImage: CIImage?

    /// The final output image with bokeh effect applied to the lifted subjects.
    @Published var output: UIImage = UIImage()

    /// An optional normalized point for selecting a subject instance.
    @Published var subjectPosition: CGPoint? = nil
    
    @Published var maskPreview: CIImage?
    @Published var outlinePath: CGPath?
    @Published var cutoutImage: UIImage?
    private var currentMask: CIImage?

    // 1. Create a single, reusable CIContext for performance.
    private let ciContext = CIContext(options: [.cacheIntermediates: true])
    private let processingQueue = DispatchQueue(label: "EffectsProcessing")
    
    // 4. Use a Set to hold cancellables and clean them up in deinit.
    private var cancellables = Set<AnyCancellable>()
    
    /// The most recent Vision task. Cancelled right before launching a new one.
    private var currentTask: Task<Void, Never>?

    init() {
        // Regenerate the composite when the pipeline input changes.
        Publishers.CombineLatest($inputImage, $subjectPosition)
            .compactMap { img, pos -> (CIImage, CGPoint?)? in
                guard let img else { return nil }
                return (img, pos)
            }
            .throttle(for: .milliseconds(200), scheduler: processingQueue, latest: true)
            .sink { [weak self] (image, position) in
            guard let self else { return }
                // Cancel any still-running Vision work
                self.currentTask?.cancel()

                // Start fresh
                self.currentTask = Task.detached(priority: .userInitiated) {
                    await self.regenerate(usingInputImage: image, subjectPosition: position)
                }
            }
            .store(in: &cancellables)
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
        currentTask?.cancel()
    }
    
    // Process image synchronously for immediate photo capture. This is not throttled.
    func processImageSync(_ inputImage: CIImage) -> UIImage {
        // Reset subject position for new images
        self.subjectPosition = nil
        
        // Generate the input-image mask.
        guard let mask = subjectMask(fromImage: inputImage, atPoint: nil) else {
            guard let cgImage = render(ciImage: inputImage) else { return UIImage() }
            return UIImage(cgImage: cgImage)
        }

        // Apply bokeh effect to subjects and composite with original background.
        let composited = applyBokehEffect(
            toInputImage: inputImage,
            mask: mask)

        guard let finalCgImage = render(ciImage: composited) else { return UIImage() }
        return UIImage(cgImage: finalCgImage)
    }

    // Refresh the pipeline and generate a new output asynchronously.
    private func regenerate(
        usingInputImage inputImage: CIImage,
        subjectPosition: CGPoint?
    ) async {
        // Check for cancellation before starting work.
        guard !Task.isCancelled else { return }
        
        // Generate the input-image mask. This is now running in a background Task.
        guard let mask = subjectMask(fromImage: inputImage, atPoint: subjectPosition) else {
            return
        }
        
        // Check for cancellation after potentially long-running mask generation.
        guard !Task.isCancelled else { return }

        // Apply bokeh effect to subjects and composite with original background.
        let composited = applyBokehEffect(
            toInputImage: inputImage,
            mask: mask)

        guard let finalCgImage = render(ciImage: composited) else { return }
        let outputImage = UIImage(cgImage: finalCgImage)

        // Publish the final image on the main thread.
        await MainActor.run {
            self.output = outputImage
        }
    }
    
    func extractSubjectWithTransparentBackground() -> UIImage? {
        guard let inputImage = inputImage else { return nil }
        
        // Generate the mask for the selected subject
        guard let mask = subjectMask(fromImage: inputImage, atPoint: subjectPosition) else {
            return nil
        }
        
        // Create transparent background
        let backgroundImage = CIImage(color: .clear)
            .cropped(to: inputImage.extent)
        
        // Composite the subject over transparent background
        let blendFilter = CIFilter.blendWithMask()
        blendFilter.inputImage = inputImage
        blendFilter.backgroundImage = backgroundImage
        blendFilter.maskImage = mask
        
        guard let composited = blendFilter.outputImage,
              let finalCgImage = render(ciImage: composited) else {
            return nil
        }
        
        return UIImage(cgImage: finalCgImage)
    }
    
    /// Renders a CIImage into a CGImage using the shared CIContext.
    private func render(ciImage img: CIImage) -> CGImage? {
        ciContext.createCGImage(img, from: img.extent)
    }
}

/// Applies bokeh effect to subjects and composites with the original background.
private func applyBokehEffect(
    toInputImage inputImage: CIImage,
    mask: CIImage
) -> CIImage {
    
    // Create bokeh effect for the background (areas not covered by subjects)
    let bokehFilter = CIFilter.bokehBlur()
    bokehFilter.inputImage = inputImage
    bokehFilter.ringSize = 1
    bokehFilter.ringAmount = 1
    bokehFilter.softness = 1.0
    bokehFilter.radius = 20
    
    guard let bokehBackground = bokehFilter.outputImage else {
        return inputImage
    }
    
    // Composite the original subjects over the bokeh background
    let blendFilter = CIFilter.blendWithMask()
    blendFilter.inputImage = inputImage  // Original subjects (sharp)
    blendFilter.backgroundImage = bokehBackground  // Bokeh background
    blendFilter.maskImage = mask  // Subject mask
    
    return blendFilter.outputImage ?? inputImage
}

/// Returns the subject alpha mask for the given image.
///
/// - parameter image: The image to extract a foreground subject from.
/// - parameter atPoint: An optional normalized point for selecting a subject instance.
private func subjectMask(fromImage image: CIImage, atPoint point: CGPoint?) -> CIImage? {
    // Create a request.
    let request = VNGenerateForegroundInstanceMaskRequest()

    // Create a request handler.
    let handler = VNImageRequestHandler(ciImage: image)

    // Perform the request.
    do {
        try handler.perform([request])
    } catch {
        print("Failed to perform Vision request: \(error)")
        return nil
    }

    // Acquire the instance mask observation.
    guard let result = request.results?.first else {
        print("No subject observations found.")
        return nil
    }

    let instances = instances(atPoint: point, inObservation: result)

    // Create a matted image with the subject isolated from the background.
    do {
        let mask = try result.generateScaledMaskForImage(forInstances: instances, from: handler)
        return CIImage(cvPixelBuffer: mask)
    } catch {
        print("Failed to generate subject mask: \(error)")
        return nil
    }
}

/// Returns the indices of the instances at the given point.
///
/// - parameter atPoint: A point with a top-left origin, normalized within the range [0, 1].
/// - parameter inObservation: The observation instance to extract subject indices from.
private func instances(
    atPoint maybePoint: CGPoint?,
    inObservation observation: VNInstanceMaskObservation
) -> IndexSet {
    guard let point = maybePoint else {
        return observation.allInstances
    }

    // Transform the normalized UI point to an instance map pixel coordinate.
    let instanceMap = observation.instanceMask
    let coords = VNImagePointForNormalizedPoint(
        point,
        CVPixelBufferGetWidth(instanceMap) - 1,
        CVPixelBufferGetHeight(instanceMap) - 1)

    // Look up the instance label at the computed pixel coordinate.
    CVPixelBufferLockBaseAddress(instanceMap, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(instanceMap, .readOnly) }
    guard let pixels = CVPixelBufferGetBaseAddress(instanceMap) else {
        print("Failed to access instance map data.")
        // Return all instances as a fallback
        return observation.allInstances
    }
    let bytesPerRow = CVPixelBufferGetBytesPerRow(instanceMap)
    let instanceLabel = pixels.load(
        fromByteOffset: Int(coords.y) * bytesPerRow + Int(coords.x),
        as: UInt8.self)

    // If the point lies on the background, select all instances.
    // Otherwise, restrict this to just the selected instance.
    return instanceLabel == 0 ? observation.allInstances : [Int(instanceLabel)]
}

