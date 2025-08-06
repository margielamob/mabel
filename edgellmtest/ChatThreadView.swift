//
//  ChatThreadView.swift
//  edgellmtest
//
//  Created by Ahmed El Shami on 2025-08-01.
//


import SwiftUI

struct ChatThreadView: View {
    @StateObject var viewModel: ChatThreadViewModel
    @State private var draftText: String = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // FR-3: Header with original translation context
            headerView
                .padding()
            
            Divider()

            // List of messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.messages) { message in
                            VStack(spacing: 0) {
                                messageView(message)
                                    .id(message.id)
                                    .padding()
                                
                                if message.id != viewModel.messages.last?.id {
                                    Divider()
                                        .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    // Auto-scroll to the newest message
                    DispatchQueue.main.async {
                        proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                    }
                }
            }
            
            Divider()

            // Input area
            inputArea
        }
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(UIColor.systemBackground))
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.translation.sourceText)
                .font(.body).fontWeight(.semibold)
                .lineLimit(2)
            
            if let firstLine = viewModel.translation.translatedText.components(separatedBy: .newlines).first {
                Text(firstLine)
                    .font(.caption)
                    .opacity(0.7)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func messageView(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.text.isEmpty && message.role == .assistant && viewModel.isProcessing {
                // Show three dots animation for empty assistant messages
                PhaseAnimator([0, 1, 2]) { phase in
                    HStack(spacing: 4) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(.secondary)
                                .frame(width: 6, height: 6)
                                .scaleEffect(phase == index ? 1.4 : 0.8)
                                .opacity(phase == index ? 1 : 0.3)
                        }
                    }
                } animation: { _ in
                    .easeInOut(duration: 0.35)
                }
                .padding(.vertical, 2)
            } else {
                Text(message.text)
                    .font(.body)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var inputArea: some View {
        HStack {
            Spacer()
            TextField("Ask about this translation...", text: $draftText)
                .textFieldStyle(.plain)
                .focused($isInputFocused)
                .disableAutocorrection(true)
                .autocapitalization(.none)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
                .disabled(viewModel.isProcessing)
                .lineLimit(1...5)
                .padding()
                .submitLabel(.send)
                                .onSubmit {
                                    if !draftText.isEmpty {
                                        viewModel.send(draftText)
                                        draftText = ""
                                        isInputFocused = false
                                    }
                                }
            Spacer()
        }
    }
}
