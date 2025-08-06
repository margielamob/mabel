//
//  WhisperService.swift
//  edgellmtest
//
//  Created by Ahmed El Shami on 2025-07-13.
//

import Foundation
import AVFoundation
import whisper                      // <- xcframework module

// MARK: - Errors
enum WhisperServiceError: Error {
    case modelNotFound
    case contextInitFailed
    case unsupportedFormat
    case transcriptionFailed(Int32)
}

/// Direct, lightweight wrapper that talks to the raw C API.
final class WhisperService {

    // MARK: Stored properties
    private let ctx: OpaquePointer          // whisper_context *
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    // MARK: Init & deinit
    init() throws {
        // 1. Locate ggml-medium-q5_0.bin in the main bundle
        guard let path = Bundle.main.path(forResource: "ggml-medium-q5_0",
                                          ofType: "bin") else {
            throw WhisperServiceError.modelNotFound
        }

        // 2. Build default context-params (GPU off, etc.)
        let cParams = whisper_context_default_params()

        // 3. Create context
        let maybeCtx: OpaquePointer? = path.withCString { cString in
            // Modern, non-deprecated entry point
            whisper_init_from_file_with_params(cString, cParams)
            // Or use whisper_init_from_file(cString) if you prefer
        }

        guard let ctx = maybeCtx else { throw WhisperServiceError.contextInitFailed }
        self.ctx = ctx
    }

    deinit { whisper_free(ctx) }

    // MARK: Recording helpers
    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker])
        try session.setActive(true)

        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask)[0]
        recordingURL = docs.appendingPathComponent("recording.wav")

        // Whisper wants 16-kHz mono Float32
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMBitDepthKey: 32
        ]
        
        guard let url = recordingURL else { throw WhisperServiceError.unsupportedFormat }
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.record()
    }

    @discardableResult
    func stopRecording() -> URL? {
        recorder?.stop()
        recorder = nil
        return recordingURL
    }

    // MARK: Transcription
    func transcribeAudio(at url: URL,
                         progress: ((Float) -> Void)? = nil) throws -> String {

        // --- 1. Load PCM -----------------------------------------------
        let file = try AVAudioFile(forReading: url)
        guard
            file.processingFormat.sampleRate == 16_000,
            file.processingFormat.channelCount == 1,
            file.processingFormat.commonFormat == .pcmFormatFloat32
        else { throw WhisperServiceError.unsupportedFormat }

        let frames = AVAudioFrameCount(file.length)
        guard let pcm =
                AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                 frameCapacity: frames) else {
            throw WhisperServiceError.unsupportedFormat
        }
        try file.read(into: pcm)

        let nSamples = Int32(pcm.frameLength)
        let samplesPtr = pcm.floatChannelData![0]

        // --- 2. Params -------------------------------------------------
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.n_threads = Int32(ProcessInfo.processInfo.activeProcessorCount)
        params.print_progress   = false
        params.print_realtime   = false
        params.print_timestamps = false
        params.print_special    = false

        if let progress = progress {
            // Bridge Swift closure to C callback
            params.progress_callback = { _, _, pct, userData in
                let closure = Unmanaged<AnyObject>
                    .fromOpaque(userData!).takeUnretainedValue() as! (Float) -> Void
                closure(Float(pct) / 100.0)
            }
            params.progress_callback_user_data =
                UnsafeMutableRawPointer(Unmanaged.passUnretained(progress as AnyObject)
                                            .toOpaque())
        }

        // --- 3. Inference ----------------------------------------------
        let status = whisper_full(ctx, params, samplesPtr, nSamples)
        guard status == 0 else {
            throw WhisperServiceError.transcriptionFailed(status)
        }

        // --- 4. Collect segments --------------------------------------
        let nSegments = whisper_full_n_segments(ctx)
        var transcript = ""
        for i in 0..<nSegments {
            if let cstr = whisper_full_get_segment_text(ctx, i) {
                transcript += String(cString: cstr)
            }
        }
        return transcript
    }
}

