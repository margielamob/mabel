//
//  AppPermission.swift
//  edgellmtest
//
//  Created by Ahmed El Shami on 2025-07-19.
//


import AVFoundation
import AVFAudio

enum AppPermission {
    case camera, microphone
}

@MainActor
final class PermissionManager: ObservableObject {
    @Published var showSettingsAlert = false   // drive an .alert()

    func ensure(_ permission: AppPermission,
                onGranted: @escaping () -> Void) {
        switch permission {
        // ────────────────── CAMERA ──────────────────
        case .camera:
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                onGranted()

            case .notDetermined:
                Task {                    // suspend without blocking UI
                    if await AVCaptureDevice.requestAccess(for: .video) {
                        onGranted()
                    } else {
                        showSettingsAlert = true
                    }
                }

            default:                     // .denied, .restricted
                showSettingsAlert = true
            }

        // ───────────────── MICROPHONE ───────────────
        case .microphone:
            let session = AVAudioSession.sharedInstance()

            switch session.recordPermission {
            case .granted:
                onGranted()                              // we already have access

            case .undetermined:
                session.requestRecordPermission { granted in
                    // hop back to the main actor for UI updates
                    Task { @MainActor in
                        if granted {
                            onGranted()
                        } else {
                            self.showSettingsAlert = true
                        }
                    }
                }

            default:                                    // .denied
                showSettingsAlert = true
            }

        }
    }
}
