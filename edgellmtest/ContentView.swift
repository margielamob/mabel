import SwiftUI
import SwiftData
import Vision
import VisionKit

struct ContentView: View {
    @StateObject private var viewModel = TranslationViewModel()
    @FocusState private var isInputFocused: Bool
    @StateObject private var tts = TTSManager()
    @State private var draftText = ""
    // MARK: - SwiftData Properties
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Translation.timestamp, order: .reverse) private var translations: [Translation]
    private var groupedTranslations: [(key: DateSection, value: [Translation])] {
        var grouped = Dictionary(grouping: translations, by: { DateSection(from: $0.timestamp) })
        if let current = viewModel.currentTranslation {
            grouped[.today, default: []].insert(current, at: 0)
        }
        
        return grouped.sorted { $0.key.rawValue < $1.key.rawValue }
    }
    @State private var selectedTranslationId: UUID?
    
    // MARK: - Permisions
    @StateObject private var perms = PermissionManager()
    @State private var navigationPath = NavigationPath()
    // MARK: - Camera Properties (NEW)
    @StateObject private var cameraModel = DataModel()
    @State private var isCameraViewPresented = false
    
    private var shouldShowCapturedPhoto: Bool {
       isCameraViewPresented && cameraModel.capturedUIImage != nil
   }
       
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if let criticalError = viewModel.criticalError {
                    VStack {
                        Spacer()
                        Text("Error")
                            .font(.headline)
                        Text(criticalError)
                            .padding()
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding()
                } else {
                    mainInterface
                }
            }
            .alert("Permission Required", isPresented: $perms.showSettingsAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Please grant Camera and/or Microphone access in Settings to use this feature.")
            }
            .task {
                viewModel.setModelContext(modelContext)
            }
            .sheet(isPresented: $isCameraViewPresented) {
                  CameraSheet(
                      model: cameraModel,
                      isPresented: $isCameraViewPresented,
                      onTranslate: { capturedImage in
                          // Object translation (existing functionality)
                          isCameraViewPresented = false
                          viewModel.processImage(capturedImage)
                      },
                      onTranslateText: { text, croppedImage in
                          // Text translation (new functionality)
                          isCameraViewPresented = false
                          viewModel.processText(
                              text,
                              sourceType: .image,
                              image: croppedImage  // Save the cropped region as thumbnail
                          )
                      }
                  )
                  .presentationDetents([.fraction(0.5)])
                  .presentationCornerRadius(20)
                  .presentationDragIndicator(.visible)
                  .ignoresSafeArea(edges: .bottom)
                  
                  .onDisappear {
                          cameraModel.resetCamera()
                      }
              }
            .navigationDestination(for: ChatThread.self) { thread in
                            // The translation object must be passed to populate the header.
                            // We find it from our main translations list.
                            if let translation = translations.first(where: { $0.id == thread.translationId }) {
                                ChatThreadView(viewModel: ChatThreadViewModel(
                                                        translation: translation,
                                                        modelContext: modelContext,
                                                        onDeviceModel: viewModel.currentOnDeviceModel,
                                                        sourceLanguageName: viewModel.sourceLanguage.name,
                                                        targetLanguageName: viewModel.targetLanguage.name
                                                    ))
                            }
                        }
        }

    }
    
    // MARK: - Main Interface (MODIFIED)
    private var mainInterface: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                languageSelectorView
                
                translationHistoryView

            }
        }
        .safeAreaInset(edge: .bottom) {
            // REPLACE the entire `bottomInputArea` property with this new view
            BottomInputView(
                isProcessing: viewModel.isProcessing,
                isModelLoading: viewModel.isModelLoading,
                isRecording: viewModel.isRecording,
                onSend: { text in
                    viewModel.processText(text)
                },
                onCamera: {
                    perms.ensure(.camera) {
                        cameraModel.resetCamera()
                        withAnimation {
                            isCameraViewPresented.toggle()
                        }
                    }
                },
                onMic: {
                    perms.ensure(.microphone) {
                        if viewModel.isRecording {
                            viewModel.stopVoiceRecordingAndProcess()
                        } else {
                            viewModel.startVoiceRecording()
                        }
                    }
                }
            )
            
        }
    }
    
    // MARK: - Language Selector View
    private var languageSelectorView: some View {
        HStack(spacing: 15) {
            Menu {
                Picker("Source Language", selection: $viewModel.sourceLanguage) {
                    ForEach(viewModel.availableLanguages) { lang in
                        Text(lang.name).tag(lang)
                    }
                }
            } label: {
                languageChip(
                    language: viewModel.sourceLanguage
                )
            }
            Button {
                let source = viewModel.sourceLanguage
                let target = viewModel.targetLanguage
                viewModel.sourceLanguage = target
                viewModel.targetLanguage = source
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.title2)
            }

            Menu {
                Picker("Target Language", selection: $viewModel.targetLanguage) {
                    ForEach(viewModel.availableLanguages) { lang in
                        Text(lang.name).tag(lang)
                    }
                }
            } label: {
                languageChip(
                    language: viewModel.targetLanguage
                )
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity)
    }
    private func languageChip(language: Language) -> some View {
        HStack {
            Text(language.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.bold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .clipShape(Capsule())
    }

    // MARK: - Translation History View
    private var translationHistoryView: some View {
        List {
            // Empty state stays exactly the same
            if translations.isEmpty && viewModel.currentTranslation == nil {
                emptyStateView
                    .listRowSeparator(.hidden)
            } else {
                // Same sectioning as before
                ForEach(groupedTranslations, id: \.key) { section in
                    Section(
                        header: Text(section.key.displayName)
                            .font(.footnote)
                            .fontWeight(.semibold)
                    ) {
                        ForEach(section.value) { translation in
                            DisclosureGroup(
                                // Bind the chevron state to your single-selection ID
                                isExpanded: Binding(
                                    get: { selectedTranslationId == translation.id },
                                    set: { expanded in selectedTranslationId = expanded ? translation.id : nil }
                                )
                            ) {
                                // --- Expanded body ----------
                                expandedTranslationView(translation)
                            } label: {
                                // --- Collapsed row ----------
                                translationRow(
                                    translation,
                                    isCurrentTranslation: translation.id == viewModel.currentTranslation?.id
                                )
                            }
                            // Swipe-to-delete logic is unchanged
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    if translation.id != viewModel.currentTranslation?.id {
                                        viewModel.deleteTranslation(id: translation.id, context: modelContext)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                                .disabled(translation.id == viewModel.currentTranslation?.id)
                            }
                            .contextMenu {
                                                           // Prevent opening chat for an in-flight translation.
                                                           if !translation.translatedText.isEmpty {
                                                               Button {
                                                                   openChat(for: translation)
                                                               } label: {
                                                                   Label("Chat About This", systemImage: "ellipsis.bubble")
                                                                   
                                                               }
                                                               .tint(.orange)
                                                               .disabled(viewModel.isModelLoading)
                                                           }
                                                       }
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                            .listRowSeparator(.hidden)
                         
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .animation(.default, value: translations.count)
    }

    // MARK: - Translation Row
    private func translationRow(
        _ translation: Translation,
        isCurrentTranslation: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: translation.sourceType == .text ? "message"
                  : translation.sourceType == .voice ? "waveform"
                  : "camera")
                .font(.title3)
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 4) {
                // Source text
                Text(translation.sourceText)
                    .font(.body)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)

               
                if isCurrentTranslation && translation.translatedText.isEmpty {
                    PhaseAnimator([0, 1, 2]) { phase in                 // ⬅︎  loops forever
                        HStack(spacing: 4) {
                            ForEach(0..<3) { index in                   // 3 dots
                                Circle()
                                    .fill(.secondary)
                                    .frame(width: 6, height: 6)
                                    .scaleEffect(phase == index ? 1.4 : 0.8)
                                    .opacity(phase == index ? 1   : 0.3)
                            }
                        }
                    } animation: { _ in
                        .easeInOut(duration: 0.35)                      // 0-1-2-0 every 350 ms
                    }
                    .padding(.vertical, 2)
                }

                else if let firstLine = translation.translatedText.components(separatedBy: .newlines).first {
                    SpeakLineButton(text: firstLine,
                                    languageCode: viewModel.targetLanguage.bcp47Code) // see step 5
                        .environmentObject(tts)
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .contentShape(Rectangle())          // keeps the whole row tappable
    }

    
    // MARK: - Expanded Translation View
    private func expandedTranslationView(_ translation: Translation) -> some View {
        let lines = translation.translatedText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return VStack(alignment: .leading, spacing: 10) {
            // L1 is target — show again as a speakable chip at the top if you like:
            if let mainTarget = lines.first {
                SpeakLineButton(text: mainTarget,
                                languageCode: viewModel.targetLanguage.bcp47Code)
                    .environmentObject(tts)
            }

            // Then the 3 (source, target) pairs: indices (1,2), (3,4), (5,6)
            ForEach(0..<3, id: \.self) { pair in
                let srcIdx = 1 + pair * 2
                let tgtIdx = srcIdx + 1
                if lines.indices.contains(srcIdx) {
                    Text(lines[srcIdx])              // source sentence (non-tappable)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if lines.indices.contains(tgtIdx) {
                    SpeakLineButton(text: lines[tgtIdx],
                                    languageCode: viewModel.targetLanguage.bcp47Code)
                        .environmentObject(tts)
                }
            }

            Text(formatDetailedTimestamp(translation.timestamp))
                .font(.caption)
                .foregroundColor(Color(UIColor.tertiaryLabel))
                .padding(.top, 2)
        }
        .padding(.leading, 52)
        .padding(.trailing, 16)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    
    // MARK: - Empty State
    private var emptyStateView: some View {
        VStack {
            Spacer()
            Text("Your translations will be shown here.")
                .font(.body)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // 6.5: Logic to open a chat, creating the thread if it doesn't exist.
    // ContentView.swift
    // ContentView.swift
    @MainActor                     // keeps everything on the UI actor
    private func openChat(for translation: Translation) {
        Task {                     // still async, but inherits MainActor isolation
            let threadID = translation.id          // ① capture once, outside the predicate

            // ② Build the descriptor, then set extra knobs on it
            var descriptor = FetchDescriptor<ChatThread>(
                predicate: #Predicate { $0.translationId == threadID }
            )
            descriptor.fetchLimit = 1              // moved out of the initializer in SD-v2

            // ③ Async fetch on the main context
            if let existing = try modelContext.fetch(descriptor).first {
                navigationPath.append(existing)    // cheap: object already loaded
                return
            }

            // ④ Create & save a new thread, using SwiftData’s async save()
            let newThread = ChatThread(translationId: threadID)
            modelContext.insert(newThread)
            try modelContext.save()          // ✅ must be awaited

            navigationPath.append(newThread)
        }
    }
    
    /// Returns the 1st, 3rd, 5th, 7th lines (target-language lines) from the 7-line response.
    func targetLines(from full: String) -> [String] {
        let lines = full
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // indices 0,2,4,6 are target lines by contract of your prompt
        return lines.enumerated()
            .compactMap { idx, line in (idx == 0 || idx % 2 == 0) ? line : nil }
    }


    private func formatTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDetailedTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Date Grouping Helper
fileprivate enum DateSection: Int, CaseIterable, Identifiable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case older
    
    var id: Int { self.rawValue }
    
    var displayName: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This Week"
        case .thisMonth: "This Month"
        case .older: "Older"
        }
    }
    
    init(from date: Date) {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            self = .today
        } else if calendar.isDateInYesterday(date) {
            self = .yesterday
        } else if let weekAgo = calendar.date(byAdding: .day, value: -7, to: .now), date > weekAgo {
            self = .thisWeek
        } else if let monthAgo = calendar.date(byAdding: .month, value: -1, to: .now), date > monthAgo {
            self = .thisMonth
        } else {
            self = .older
        }
    }
}

// A helper to get the start of the current day
extension Date {
    static var now: Date { .init() }
}

#Preview {
    NavigationStack {
        ContentView()
    }
}

/*
 NOTE: The following are placeholder implementations for components
 that were part of your project but not included in the prompt.
 These are necessary for the code to be complete.
*/

enum SourceType: Codable {
    case text, voice, camera
}

// Updated CameraSheet implementation
struct CameraSheet: View {
    @ObservedObject var model: DataModel
    @Binding var isPresented: Bool
    let onTranslate: (UIImage) -> Void
    let onTranslateText: ((String, UIImage?) -> Void)?
    
    init(model: DataModel,
         isPresented: Binding<Bool>,
         onTranslate: @escaping (UIImage) -> Void,
         onTranslateText: ((String, UIImage?) -> Void)? = nil) {
        self.model = model
        self._isPresented = isPresented
        self.onTranslate = onTranslate
        self.onTranslateText = onTranslateText
    }

    var body: some View {
        ZStack {
            switch model.cameraMode {
            case .preview:
                BottomCameraView(model: model, isPresented: $isPresented)
                
            case .captured(let uiImage):
                CapturedPhotoView(
                    capturedUIImage: uiImage,
                    processedUIImage: $model.processedUIImage,
                    effectsPipeline: model.effectsPipeline,
                    dismissAction: {
                        // Reset to live camera
                        model.resetCamera()
                    },
                    onTranslate: onTranslate,
                    onTextRecognition: {
                        // Switch to text recognition mode
                        model.enterTextRecognitionMode()
                    }
                )
                
            case .textRecognition(let uiImage):
                TextSelectionView(
                    capturedImage: uiImage,
                    onDismiss: {
                        // Back to captured photo view
                        if let capturedImage = model.capturedUIImage {
                            model.cameraMode = .captured(capturedImage)
                        } else {
                            model.cameraMode = .preview
                        }
                    },
                    onTranslate: { text, croppedImage in
                        // Handle text translation
                        isPresented = false
                        onTranslateText?(text, croppedImage)
                        
                        // Reset camera
                        model.resetCamera()
                    }
                )
            }
        }
    }
}
