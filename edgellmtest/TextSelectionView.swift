import SwiftUI
import Vision

struct TextSelectionView: View {
    let capturedImage: UIImage
    let onDismiss: () -> Void
    let onTranslate: (String, UIImage?) -> Void
    
    @State private var detectedBlocks: [DetectedTextBlock] = []
    @State private var selectedBlock: DetectedTextBlock?
    @State private var isProcessing = true
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showBlocks = false
    
    private let textRecognitionService = TextRecognitionService()
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background image
                Image(uiImage: capturedImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                
                // Text block overlays
                if showBlocks && !isProcessing {
                    ForEach(Array(detectedBlocks.enumerated()), id: \.element.id) { index, block in
                        TextBlockOverlay(
                            block: block,
                            imageSize: geo.size,
                            isSelected: selectedBlock?.id == block.id,
                            onTap: { selectBlock(block) }
                        )
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeInOut(duration: 0.2).delay(Double(index) * 0.05)),
                            removal: .opacity
                        ))
                    }
                }
                
                // Loading indicator
                if isProcessing {
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("Detecting text...")
                            .font(.subheadline)
                            .foregroundColor(.white)
                            .padding(.top)
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(12)
                }
            }
        }
        .overlay(alignment: .bottom) {
            controlsOverlay
        }
        .task {
            await performTextRecognition()
        }
        .alert("No Text Found", isPresented: $showError) {
            Button("OK") {
                onDismiss()
            }
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Controls Overlay
    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            // Selected text preview
            if let selected = selectedBlock {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected Text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(selected.text)
                        .font(.body)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
                .background(.regularMaterial)
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Action buttons
            HStack(spacing: 20) {
                // Retake button
                Button(action: onDismiss) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title2)
                        Text("Retake")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .frame(width: 60, height: 50)
                  
                    .cornerRadius(12)
                }
                
                // Translate button
                if selectedBlock != nil {
                    Button(action: translateSelectedText) {
                        VStack(spacing: 4) {
                            Image(systemName: "translate")
                                .font(.title2)
                            Text("Translate")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(width: 60, height: 50)
                        .cornerRadius(12)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: selectedBlock?.id)
    }
    
    // MARK: - Methods
    private func performTextRecognition() async {
        do {
            let blocks = try await textRecognitionService.recognizeText(in: capturedImage)
            
            await MainActor.run {
                if blocks.isEmpty {
                    errorMessage = "No text found in the image. Try reframing or better lighting."
                    showError = true
                } else {
                    detectedBlocks = blocks
                    // Auto-select if only one block
                    if blocks.count == 1 {
                        selectedBlock = blocks.first
                    }
                    isProcessing = false
                    // Animate blocks appearing
                    withAnimation {
                        showBlocks = true
                    }
                }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
                isProcessing = false
            }
        }
    }
    
    private func selectBlock(_ block: DetectedTextBlock) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedBlock?.id == block.id {
                selectedBlock = nil
            } else {
                selectedBlock = block
            }
        }
    }
    
    private func translateSelectedText() {
        guard let selected = selectedBlock else { return }
        
        // Create cropped image of the selected region
        let croppedImage = textRecognitionService.cropImage(capturedImage, to: selected.boundingBox)
        
        // Send to translation
        onTranslate(selected.text, croppedImage)
    }
}

// MARK: - Text Block Overlay
struct TextBlockOverlay: View {
    let block: DetectedTextBlock
    let imageSize: CGSize
    let isSelected: Bool
    let onTap: () -> Void
    
    private var overlayRect: CGRect {
        block.viewRect(in: imageSize)
    }
    
    private var tapTargetRect: CGRect {
        // Ensure minimum 44x44pt tap target as per Apple HIG
        let minSize: CGFloat = 44
        let expandedRect = CGRect(
            x: overlayRect.midX - max(overlayRect.width, minSize) / 2,
            y: overlayRect.midY - max(overlayRect.height, minSize) / 2,
            width: max(overlayRect.width, minSize),
            height: max(overlayRect.height, minSize)
        )
        return expandedRect
    }
    
    var body: some View {
            ZStack {
                // Invisible tap target (unchanged)
                Color.clear
                    .frame(width: tapTargetRect.width, height: tapTargetRect.height)
                    .contentShape(Rectangle())
                    .position(x: overlayRect.midX, y: overlayRect.midY)
                    .onTapGesture { onTap() }

                // ──‑‑ Replace this whole rectangle style ‑‑──
                RoundedRectangle(cornerRadius: 8)
                    // Grey fill (looks like Photos “Live Text” preview)
                    .fill(
                        isSelected
                        ? Color.blue.opacity(0.25)      // keep the blue when selected
                        : Color(.systemGray).opacity(0.25)
                    )
                    .frame(width: overlayRect.width, height: overlayRect.height)
                    .position(x: overlayRect.midX, y: overlayRect.midY)
                    .scaleEffect(isSelected ? 1.02 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            }
            .allowsHitTesting(true)
        }
}
