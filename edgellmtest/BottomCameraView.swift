//
//  BottomCameraView.swift
//  edgellmtest
//
//  Created by Ahmed El Shami on 2025-07-23.
//

import SwiftUI
import AVFoundation

/// A container view that correctly handles the layout of the preview layer.
final class PreviewContainer: UIView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(_ layer: AVCaptureVideoPreviewLayer) {
        self.previewLayer = layer
        super.init(frame: .zero)
        self.backgroundColor = .black
        self.layer.addSublayer(layer)
        layer.videoGravity = .resizeAspectFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// This is the key method that ensures the preview layer is resized correctly.
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = self.bounds
    }
}


/// A SwiftUI view that wraps the PreviewContainer.
struct CameraPreviewView: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewContainer {
        return PreviewContainer(layer)
    }

    func updateUIView(_ uiView: PreviewContainer, context: Context) {
        // No updates needed here, as layoutSubviews handles resizing.
    }
}

struct BottomCameraView: View {
    @ObservedObject var model: DataModel
    @Binding var isPresented: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CameraPreviewView(layer: model.camera.previewLayer)
                    .frame(width: geo.size.width, height: geo.size.height)

                VStack {
                    Spacer()
                    buttonsView()
                        .padding(.bottom)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .mask(TopRoundedRectangle())
            .ignoresSafeArea(edges: .bottom)
        }
        .task {
            await model.camera.start()
            
        }
        .onDisappear {
            Task {
                model.camera.stop()
            }
        }
    }

    /// Reusable view for camera action buttons.
    private func buttonsView() -> some View {
        HStack {
            Spacer()
            
            Button {
                Task {
                    model.camera.takePhoto()
                }
            } label: {
                Label {
                    Text("Take Photo")
                } icon: {
                    ZStack {
                        Circle()
                            .strokeBorder(.white, lineWidth: 3)
                            .frame(width: 62, height: 62)
                        Circle()
                            .fill(.white)
                            .frame(width: 50, height: 50)
                    }
                }
            }
            
            Spacer()
        }
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
    }
}

private struct TopRoundedRectangle: Shape {
    var radius: CGFloat = 24
    func path(in rect: CGRect) -> Path {
        let corners: UIRectCorner = [.topLeft, .topRight]
        let path = UIBezierPath(roundedRect: rect,
                                byRoundingCorners: corners,
                                cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}
