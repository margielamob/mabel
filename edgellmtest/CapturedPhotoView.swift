//
//  CapturedPhotoView.swift
//  cam
//
//  Created by Ahmed El Shami on 2025-07-23.
//

import SwiftUI
import Combine

struct CapturedPhotoView: View {
    let capturedUIImage: UIImage
    @Binding var processedUIImage: UIImage?
    let effectsPipeline: EffectsPipeline
    let dismissAction: () -> Void
    let onTranslate: (UIImage) -> Void
    let onTextRecognition: () -> Void
    
    // Create Image views on-demand from UIImage data
    private var displayImage: Image {
        if let processed = processedUIImage {
            return Image(uiImage: processed)
        } else {
            return Image(uiImage: capturedUIImage)
        }
    }
    
    var body: some View {
        GeometryReader { geo in
            displayImage
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .ignoresSafeArea()
                .onTapGesture { loc in
                    effectsPipeline.subjectPosition =
                        CGPoint(x: loc.x / geo.size.width,
                                y: loc.y / geo.size.height)
                }
        }
        .overlay(alignment: .bottom) {
            controlsOverlay
        }
        .compositingGroup()
        .onReceive(effectsPipeline.$output) { uiImg in
            if uiImg.size.width > 0 {
                processedUIImage = uiImg
            }
        }
    }
    
    @ViewBuilder
    private var controlsOverlay: some View {
        VStack {
            Spacer()
            HStack(spacing: 30) {
                // Retake button
                Button(action: dismissAction) {
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
                
                // Text recognition button
                Button(action: onTextRecognition) {
                    VStack(spacing: 4) {
                        Image(systemName: "text.viewfinder")
                            .font(.title2)
                        Text("Text")
                            .font(.caption)
                    }
                    .foregroundColor(.white)
                    .frame(width: 60, height: 50)
                    .cornerRadius(12)
                }
                
                // Object translation button (only if subject selected)
                if effectsPipeline.subjectPosition != nil {
                    Button(action: {
                        onTranslate(effectsPipeline.output)
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                            Text("Object")
                                .font(.caption)
                        }
                        .foregroundColor(.white)
                        .frame(width: 60, height: 50)
                        .cornerRadius(12)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.bottom)
            .animation(.easeInOut(duration: 0.2), value: effectsPipeline.subjectPosition)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
