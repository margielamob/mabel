//
//  SpeakLineButton.swift
//  edgellmtest
//
//  Created by Ahmed El Shami on 2025-08-02.
//


import SwiftUI

struct SpeakLineButton: View {
    @EnvironmentObject var tts: TTSManager
    let text: String
    let languageCode: String
    
    var body: some View {
        HStack(spacing: 8) {
            Button {
                tts.speak(text, languageCode: languageCode)
            } label: {
                Image(systemName: "speaker.wave.2")
                    .foregroundColor(.blue)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Speak: \(text)")
            .accessibilityHint("Tap to hear pronunciation.")
            
            Text(text)
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
