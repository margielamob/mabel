//
//  TTSManager.swift
//  edgellmtest
//
//  Created by Ahmed El Shami on 2025-08-02.
//


import Foundation
import AVFoundation

@MainActor
final class TTSManager: NSObject, ObservableObject {
    @Published private(set) var currentlySpokenText: String?
    private let synthesizer = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()

    override init() {
        super.init()
        synthesizer.delegate = self
        // Preconfigure so first speak is fast
        try? audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    func speak(_ text: String, languageCode: String) {
        if currentlySpokenText == text, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            return
        }

        try? audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let utterance = AVSpeechUtterance(string: text)

        // Prefer a female voice for the requested language (exact or base match)
        let base = languageCode.split(separator: "-").first.map(String.init) ?? languageCode
        if let female = AVSpeechSynthesisVoice.speechVoices().first(where: {
            ($0.language == languageCode || $0.language.hasPrefix("\(base)-")) && $0.gender == .female
        }) {
            utterance.voice = female
        } else if let fallback = AVSpeechSynthesisVoice(language: languageCode) {
            utterance.voice = fallback
        }

        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.preUtteranceDelay = 0.02
        utterance.postUtteranceDelay = 0.02

        currentlySpokenText = text
        synthesizer.speak(utterance)
    }


    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}

extension TTSManager: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        currentlySpokenText = nil
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        currentlySpokenText = nil
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
