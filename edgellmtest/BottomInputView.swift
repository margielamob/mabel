//
//  BottomInputView.swift
//  edgellmtest
//
//  Created by Ahmed El Shami on 2025-07-31.
//


import SwiftUI

struct BottomInputView: View {
    @State private var draftText = ""
    @FocusState private var isInputFocused: Bool

    // Inputs from the parent view
    let isProcessing: Bool
    let isModelLoading: Bool
    let isRecording: Bool

    // Closures for actions
    let onSend: (String) -> Void
    let onCamera: () -> Void
    let onMic: () -> Void

    var body: some View {
        ZStack {
            // Main input content
            VStack(spacing: 16) {
                HStack {
                    Spacer()

                    // This TextField now only causes this view to update
                    TextField("Type text to translate", text: $draftText)
                        .focused($isInputFocused)
                        .submitLabel(.send)
                        .onSubmit(send)
                        .frame(maxWidth: 300)
                        .textFieldStyle(.plain)
                        .disableAutocorrection(true)
                        .autocapitalization(.none)
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.primary)
                        .accentColor(.blue)
                        .disabled(isProcessing || isModelLoading)

                    Spacer()
                }
                .padding(.top, 8)

                HStack(spacing: 32) {
                    Spacer()

                    // Camera Button
                    Button {
                        isInputFocused = false // Dismiss keyboard first
                        onCamera()
                    } label: {
                        Image(systemName: "camera")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                  
                    // Voice Button
                    Button(action: onMic) {
                        Image(systemName: "waveform")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .background(
                                isRecording ? Circle().fill(Color.red) : nil
                            )
                    }
                    .disabled(isProcessing || isModelLoading)

                    Spacer()
                }
                .padding(.bottom, 8)
            }
            .background(Color(UIColor.systemBackground))
            
            // Show loading overlay when model is loading
            if isModelLoading {
                loadingOverlay
            }
        }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .bottom))
        )
    }

    private var loadingOverlay: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
                .padding()
            Text("Loading model...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .ignoresSafeArea()
        .background(Color(UIColor.systemBackground))
    }

    private func send() {
        let text = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSend(text) // Use the closure to communicate back to the parent
        draftText = "" // Reset for the next entry
        isInputFocused = false
    }
}
