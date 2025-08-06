/*
See the License.txt file for this sample's licensing information.
*/

@preconcurrency import AVFoundation
import CoreImage
import UIKit
import os.log

final class Camera: NSObject, @unchecked Sendable {
    private let captureSession = AVCaptureSession()
    private var isCaptureSessionConfigured = false
    private var deviceInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    private var sessionQueue: DispatchQueue!
    
    // Use a preview layer for GPU-accelerated rendering.
    let previewLayer: AVCaptureVideoPreviewLayer
    
    private var allCaptureDevices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices
    }
    
    private var frontCaptureDevices: [AVCaptureDevice] {
        allCaptureDevices.filter { $0.position == .front }
    }
    
    private var backCaptureDevices: [AVCaptureDevice] {
        allCaptureDevices.filter { $0.position == .back }
    }
    
    private var captureDevices: [AVCaptureDevice] {
        var devices = [AVCaptureDevice]()
        #if os(macOS) || (os(iOS) && targetEnvironment(macCatalyst))
        devices += allCaptureDevices
        #else
        if let backDevice = backCaptureDevices.first {
            devices.append(backDevice)
        }
        if let frontDevice = frontCaptureDevices.first {
            devices.append(frontDevice)
        }
        #endif
        return devices
    }
    
    private var availableCaptureDevices: [AVCaptureDevice] {
        captureDevices.filter { $0.isConnected && !$0.isSuspended }
    }
    
    private var captureDevice: AVCaptureDevice? {
        didSet {
            guard let captureDevice = captureDevice else { return }
            logger.debug("Using capture device: \(captureDevice.localizedName)")
            sessionQueue.async {
                self.updateSessionForCaptureDevice(captureDevice)
            }
        }
    }
    
    var isRunning: Bool {
        captureSession.isRunning
    }
    
    var isUsingFrontCaptureDevice: Bool {
        guard let captureDevice = captureDevice else { return false }
        return frontCaptureDevices.contains(captureDevice)
    }
    
    var isUsingBackCaptureDevice: Bool {
        guard let captureDevice = captureDevice else { return false }
        return backCaptureDevices.contains(captureDevice)
    }

    private var addToPhotoStream: ((UIImage) -> Void)?
    
    lazy var photoStream: AsyncStream<UIImage> = {
        AsyncStream { [weak self] continuation in
            self?.addToPhotoStream = { image in
                continuation.yield(image)
            }
        }
    }()
        
    override init() {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        super.init()
        initialize()
    }
    
    private func initialize() {
        sessionQueue = DispatchQueue(label: "session queue")
        
        captureDevice = availableCaptureDevices.first ?? AVCaptureDevice.default(for: .video)
        
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(self, selector: #selector(updateForDeviceOrientation), name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    
    private func configureCaptureSession(completionHandler: (_ success: Bool) -> Void) {
        
        var success = false
        
        self.captureSession.beginConfiguration()
        
        defer {
            self.captureSession.commitConfiguration()
            completionHandler(success)
        }
        
        guard
            let captureDevice = captureDevice,
            let deviceInput = try? AVCaptureDeviceInput(device: captureDevice)
        else {
            logger.error("Failed to obtain video input.")
            return
        }
        
        let photoOutput = AVCapturePhotoOutput()
                        
        captureSession.sessionPreset = .high
  
        guard captureSession.canAddInput(deviceInput) else {
            logger.error("Unable to add device input to capture session.")
            return
        }
        guard captureSession.canAddOutput(photoOutput) else {
            logger.error("Unable to add photo output to capture session.")
            return
        }
        
        captureSession.addInput(deviceInput)
        captureSession.addOutput(photoOutput)
        
        self.deviceInput = deviceInput
        self.photoOutput = photoOutput
        
        if let maxDimensions = captureDevice.activeFormat.supportedMaxPhotoDimensions.last {
            photoOutput.maxPhotoDimensions = maxDimensions
        }
        photoOutput.maxPhotoQualityPrioritization = .quality
        
        updateVideoOutputConnection()
        
        updateForDeviceOrientation()
        
        isCaptureSessionConfigured = true
        
        success = true
    }
    
    private func checkAuthorization() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            logger.debug("Camera access authorized.")
            return true
        case .notDetermined:
            logger.debug("Camera access not determined.")
            sessionQueue.suspend()
            let status = await AVCaptureDevice.requestAccess(for: .video)
            sessionQueue.resume()
            return status
        case .denied:
            logger.debug("Camera access denied.")
            return false
        case .restricted:
            logger.debug("Camera library access restricted.")
            return false
        @unknown default:
            return false
        }
    }
    
    private func deviceInputFor(device: AVCaptureDevice?) -> AVCaptureDeviceInput? {
        guard let validDevice = device else { return nil }
        do {
            return try AVCaptureDeviceInput(device: validDevice)
        } catch let error {
            logger.error("Error getting capture device input: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func updateSessionForCaptureDevice(_ captureDevice: AVCaptureDevice) {
        guard isCaptureSessionConfigured else { return }
        
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        for input in captureSession.inputs {
            if let deviceInput = input as? AVCaptureDeviceInput {
                captureSession.removeInput(deviceInput)
            }
        }
        
        if let deviceInput = deviceInputFor(device: captureDevice) {
            if !captureSession.inputs.contains(deviceInput), captureSession.canAddInput(deviceInput) {
                captureSession.addInput(deviceInput)
            }
        }
        
        updateVideoOutputConnection()
    }
    
    private func updateVideoOutputConnection() {
        if let previewLayerConnection = previewLayer.connection, previewLayerConnection.isVideoMirroringSupported {
            previewLayerConnection.automaticallyAdjustsVideoMirroring = false
            previewLayerConnection.isVideoMirrored = isUsingFrontCaptureDevice
        }
        if let photoOutputConnection = photoOutput?.connection(with: .video), photoOutputConnection.isVideoMirroringSupported {
            photoOutputConnection.automaticallyAdjustsVideoMirroring = false
            photoOutputConnection.isVideoMirrored = isUsingFrontCaptureDevice
        }
    }
    
    func start() async {
        let authorized = await checkAuthorization()
        guard authorized else {
            logger.error("Camera access was not authorized.")
            return
        }
        
        if isCaptureSessionConfigured {
            if !captureSession.isRunning {
                sessionQueue.async { [weak self] in
                    self?.captureSession.startRunning()
                }
            }
            return
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.configureCaptureSession { success in
                guard success else { return }
                self.captureSession.startRunning()
            }
        }
    }
    
    func stop() {
        guard isCaptureSessionConfigured else { return }
        
        if captureSession.isRunning {
            sessionQueue.async {
                self.captureSession.stopRunning()
            }
        }
    }
    
    func switchCaptureDevice() {
        if let captureDevice = captureDevice, let index = availableCaptureDevices.firstIndex(of: captureDevice) {
            let nextIndex = (index + 1) % availableCaptureDevices.count
            self.captureDevice = availableCaptureDevices[nextIndex]
        } else {
            self.captureDevice = AVCaptureDevice.default(for: .video)
        }
    }
    
    private func videoRotationAngleFor(_ deviceOrientation: UIDeviceOrientation) -> CGFloat {
        switch deviceOrientation {
        case .portrait:
            return 90
        case .portraitUpsideDown:
            return 270
        case .landscapeLeft:
            return 180
        case .landscapeRight:
            return 0
        default:
            return 90
        }
    }
    
    @objc
    func updateForDeviceOrientation() {
        let currentOrientation = UIDevice.current.orientation
        let rotationAngle = videoRotationAngleFor(currentOrientation)
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            if let previewConnection = self.previewLayer.connection, previewConnection.isVideoRotationAngleSupported(rotationAngle) {
                previewConnection.videoRotationAngle = rotationAngle
            }
            
            if let photoConnection = self.photoOutput?.connection(with: .video), photoConnection.isVideoRotationAngleSupported(rotationAngle) {
                photoConnection.videoRotationAngle = rotationAngle
            }
        }
    }
    
    func takePhoto() {
        guard let photoOutput = self.photoOutput else { return }
        
        sessionQueue.async {
            
            var photoSettings = AVCapturePhotoSettings()

            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            
            let isFlashAvailable = self.deviceInput?.device.isFlashAvailable ?? false
            photoSettings.flashMode = isFlashAvailable ? .auto : .off
            
            if let previewPhotoPixelFormatType = photoSettings.availablePreviewPhotoPixelFormatTypes.first {
                photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: previewPhotoPixelFormatType]
            }
            photoSettings.photoQualityPrioritization = .balanced
            
            photoOutput.capturePhoto(with: photoSettings, delegate: self)
        }
    }
}

extension Camera: AVCapturePhotoCaptureDelegate {
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        
        guard error == nil,
                 let data = photo.fileDataRepresentation(),
                 var uiImage = UIImage(data: data) else { return }

           // Make the photo match the preview
           uiImage = uiImage.cropped(to: previewLayer)

           addToPhotoStream?(uiImage)


    }
}

extension UIImage {
    /// Crops the image so that it matches exactly what was visible
    /// in the supplied `AVCaptureVideoPreviewLayer`.
    func cropped(to previewLayer: AVCaptureVideoPreviewLayer) -> UIImage {
        // 1. Preview‑layer rect ➜ normalised rect (0–1 coordinate space)
        let outputRect = previewLayer
            .metadataOutputRectConverted(fromLayerRect: previewLayer.bounds)

        guard let cg = self.cgImage else { return self }

        // 2. Convert that rect to pixel coordinates in the captured photo
        let pixelCrop = CGRect(
            x: outputRect.origin.x * CGFloat(cg.width),
            y: outputRect.origin.y * CGFloat(cg.height),
            width: outputRect.size.width * CGFloat(cg.width),
            height: outputRect.size.height * CGFloat(cg.height)
        ).integral

        // 3. Crop and return
        guard let croppedCG = cg.cropping(to: pixelCrop) else { return self }
        return UIImage(cgImage: croppedCG,
                       scale: self.scale,
                       orientation: self.imageOrientation)
    }
}


fileprivate let logger = Logger(subsystem: "com.apple.swiftplaygroundscontent.capturingphotos", category: "Camera")
