import Foundation
import Combine
import UIKit
import SwiftUI
import AVFoundation
import Vision
import SwiftData

@Model
final class Translation {
    @Attribute(.unique)
    var id: UUID
    var sourceText: String
    var translatedText: String
    var timestamp: Date
    var sourceType: SourceType
    
    // Storing raw data
    private var sourceImageData: Data?
    private var stickerImageData: Data?
    
    enum SourceType: Codable {
        case text
        case voice
        case image
    }
    
    init(id: UUID = UUID(),
         sourceText: String,
         translatedText: String,
         timestamp: Date = .now,
         sourceType: SourceType,
         sourceImage: UIImage? = nil,
         stickerImage: UIImage? = nil) {
        self.id = id
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.timestamp = timestamp
        self.sourceType = sourceType
        // Convert UIImages to Data for storage
        self.sourceImageData = sourceImage?.pngData()
        self.stickerImageData = stickerImage?.pngData()
    }
    
    var sourceImage: UIImage? {
        guard let data = sourceImageData else { return nil }
        return UIImage(data: data)
    }
    
    var stickerImage: UIImage? {
        guard let data = stickerImageData else { return nil }
        return UIImage(data: data)
    }
}

@MainActor
class TranslationViewModel: ObservableObject {
    private var modelContext: ModelContext?
    // MARK: - Published Properties
    @Published var isModelLoading: Bool = true
    @Published var isProcessing: Bool = false
    @Published var currentTranslation: Translation?
    @Published var expandedTranslationId: UUID?
    
    @Published var modelInitializationTime: Double = 0.0
    @Published var lastResponseTokenCount: Int = 0
    @Published var lastResponseLibraryTime: Double = 0.0
    @Published var lastResponseTokensPerSecond: Double = 0.0

    @Published var criticalError: String?
    
    // MARK: - Model Switching State
    @Published public var availableModels: [ModelIdentifier] = []
    @AppStorage("selectedModelIdentifierRawValue") private var selectedModelIdentifierRawValue: String = ModelIdentifier.gemma2B.rawValue
    
    // MARK: - Audio / Whisper State
    private let whisperService: WhisperService? = try? WhisperService()
    @Published var isRecording: Bool = false
    @Published var micError: String?

    // MARK: - NEW: Language Selection Properties
    @Published var availableLanguages: [Language] = Language.all
    @AppStorage("sourceLanguageId") private var sourceLanguageId: String = Language.french.id
    @AppStorage("targetLanguageId") private var targetLanguageId: String = Language.english.id

    
    // MARK: - Model loading task
    private var modelLoadTask: Task<Void, Never>?

    var sourceLanguage: Language {
        get { availableLanguages.first { $0.id == sourceLanguageId } ?? .french }
        set { sourceLanguageId = newValue.id }
    }
    var targetLanguage: Language {
        get { availableLanguages.first { $0.id == targetLanguageId } ?? .english }
        set { targetLanguageId = newValue.id }
    }
    
    public var selectedModelIdentifier: ModelIdentifier {
        get { ModelIdentifier(rawValue: selectedModelIdentifierRawValue) ?? .gemma2B }
        set { selectedModelIdentifierRawValue = newValue.rawValue }
    }
    
    // MARK: - Inference Settings
    @AppStorage("inferenceTopK_v1") public var topK: Int = 40
    @AppStorage("inferenceTopP_v1") public var topP: Double = 0.8
    @AppStorage("inferenceTemperature_v1") public var temperature: Double = 0.2
    @AppStorage("inferenceEnableVisionModality_v1") public var enableVisionModality: Bool = true
    
    // MARK: - Private LLM State
    var currentOnDeviceModel: OnDeviceModel?
    var currentChat: Chat?
    private var processingTask: Task<Void, Error>?
    
    
    // MARK: - Initialization
    init() {
        self.availableModels = ModelIdentifier.availableInBundle()
        Task {
            _ = await AVAudioApplication.requestRecordPermission()
        }
        
        if availableModels.isEmpty {
            let noModelsErrorMessage = "Critical Error: No LLM models found in the app bundle."
            NSLog(noModelsErrorMessage)
            criticalError = noModelsErrorMessage
            isModelLoading = false
            return
        }
        
        var initialModelToLoad = ModelIdentifier.gemma2B
        let preferredModelFromStorage = ModelIdentifier(rawValue: selectedModelIdentifierRawValue)
        if let prefModel = preferredModelFromStorage, availableModels.contains(prefModel) {
            initialModelToLoad = prefModel
        } else if availableModels.contains(.gemma2B) {
            initialModelToLoad = .gemma2B
        } else if let firstAvailable = availableModels.first {
            initialModelToLoad = firstAvailable
        }
        
        self.selectedModelIdentifier = initialModelToLoad

        loadAndInitializeModel(selectedModelIdentifier)
        
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    // MARK: - Model Management
    func loadAndInitializeModel(_ id: ModelIdentifier) {
            modelLoadTask?.cancel()

            isModelLoading = true
            criticalError  = nil

            modelLoadTask = Task.detached(priority: .userInitiated) { [topK, topP,
                                                                        temperature,
                                                                        enableVisionModality] in
                guard !Task.isCancelled else { return }

                do {
                    let model = try OnDeviceModel(modelIdentifier: id)
                    let chat  = try Chat(model: model,
                                         topK: topK,
                                         topP: Float(topP),
                                         temperature: Float(temperature),
                                         enableVisionModality: enableVisionModality)

                    let initTime = model.inference.metrics.initializationTimeInSeconds
                    await MainActor.run {
                        guard !Task.isCancelled else { return }
                        self.currentOnDeviceModel = model
                        self.currentChat          = chat
                        self.modelInitializationTime = initTime
                        self.isModelLoading = false
                    }
                } catch is CancellationError {
                } catch {
                    await MainActor.run {
                        self.criticalError  = error.localizedDescription
                        self.isModelLoading = false
                    }
                }
            }
        }

        deinit { modelLoadTask?.cancel() }
    
    // MARK: - Translation Processing
    func processText(
        _ text: String,
        sourceType: Translation.SourceType = .text,
        image: UIImage? = nil,
        sticker: UIImage? = nil
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        processingTask?.cancel()

        processingTask = Task {
            defer {
                Task { @MainActor in
                    self.isProcessing = false
                    self.processingTask = nil
                }
            }

            do {
                try Task.checkCancellation()
                guard let chat = currentChat else {
                    NSLog("Chat session is not ready")
                    return
                }
                let prompt: String
                let sourceTextForCard: String
                // This is a standard text translation
                prompt = PromptBuilder.translationPrompt(
                    sourceText: text,
                    sourceLang: sourceLanguage.name,
                    targetLang: targetLanguage.name
                )
                sourceTextForCard = text
                
                await MainActor.run {
                    self.currentTranslation = Translation(
                        sourceText: sourceTextForCard,
                        translatedText: "",
                        sourceType: sourceType,
                        sourceImage: image,
                        stickerImage: sticker
                    )
                    self.isProcessing = true
                }

                let rawStream = try await chat.sendMessage(prompt)

                let throttle = Duration.milliseconds(30)
                var lastEmit = ContinuousClock.now
                var pending   = ""
                var total     = ""

                for try await piece in rawStream {
                    try Task.checkCancellation()
                    pending += piece
                    total   += piece

                    let now = ContinuousClock.now
                    if now - lastEmit >= throttle {
                        let chunk = pending
                        pending.removeAll()
                        lastEmit = now
                        await MainActor.run {
                            self.currentTranslation?.translatedText += chunk
                        }
                    }
                }

                if !pending.isEmpty {
                    await MainActor.run {
                        self.currentTranslation?.translatedText += pending
                    }
                }

                let finishedTranslation = await MainActor.run { self.currentTranslation }
                Task {
                    try await Task.sleep(for: .seconds(3))
                    await MainActor.run {
                        guard let context = self.modelContext else { return }
                        
                        if let card = finishedTranslation,
                           self.currentTranslation?.id == card.id {
                            // Create a new persistent Translation object from the temporary one.
                            let persistentTranslation = Translation(
                                id: card.id,
                                sourceText: card.sourceText,
                                translatedText: card.translatedText,
                                timestamp: card.timestamp,
                                sourceType: card.sourceType,
                                sourceImage: card.sourceImage,
                                stickerImage: card.stickerImage
                            )
                            context.insert(persistentTranslation)
                            self.currentTranslation = nil
                        }
                    }
                }

                if !total.isEmpty {
                    self.lastResponseTokenCount = (try? chat.sizeInTokens(text: total)) ?? 0
                }
                if let t = chat.getLastResponseGenerationTime() {
                    self.lastResponseLibraryTime = t
                }
                if self.lastResponseLibraryTime > 0 && self.lastResponseTokenCount > 0 {
                    self.lastResponseTokensPerSecond =
                        Double(self.lastResponseTokenCount) / self.lastResponseLibraryTime
                }

            } catch is CancellationError {
                NSLog("Processing was cancelled.")
            } catch {
                NSLog("Error during processing: \(error.localizedDescription)")
            }
        }
    }
    
    func processImage(_ extractedSubjectImage: UIImage) {
        processingTask?.cancel()
        
        processingTask = Task {
            defer {
                Task { @MainActor in
                    self.isProcessing = false
                    self.processingTask = nil
                }
            }
            
            do {
                try Task.checkCancellation()
                guard let chat = currentChat else {
                    NSLog("Chat session is not ready")
                    return
                }
                
                // Convert UIImage to CGImage
                guard let cgImage = extractedSubjectImage.cgImage else {
                    NSLog("Failed to convert UIImage to CGImage")
                    return
                }
                
                // Add image to the chat context
                try chat.addImageToQuery(image: cgImage)
                print(sourceLanguage.name)
                print(targetLanguage.name)
                let prompt = PromptBuilder.imageTranslationPrompt(
                    sourceLang: sourceLanguage.name,
                    targetLang: targetLanguage.name
                )
                
                await MainActor.run {
                    self.currentTranslation = Translation(
                        sourceText: "Image",
                        translatedText: "",
                        sourceType: .image,
                        sourceImage: extractedSubjectImage
                    )
                    self.isProcessing = true
                }
                
                let rawStream = try await chat.sendMessage(prompt)
                
                let throttle = Duration.milliseconds(15)
                var lastEmit = ContinuousClock.now
                var pending   = ""
                var total     = ""
                
                for try await piece in rawStream {
                    try Task.checkCancellation()
                    pending += piece
                    total   += piece
                    
                    let now = ContinuousClock.now
                    if now - lastEmit >= throttle {
                        let chunk = pending
                        pending.removeAll()
                        lastEmit = now
                        await MainActor.run {
                            self.currentTranslation?.translatedText += chunk
                        }
                    }
                }
                
                if !pending.isEmpty {
                    await MainActor.run {
                        self.currentTranslation?.translatedText += pending
                    }
                }
                
                let finishedTranslation = await MainActor.run { self.currentTranslation }
                Task {
                    try await Task.sleep(for: .seconds(3))
                    await MainActor.run {
                        guard let context = self.modelContext else { return }
                        
                        if let card = finishedTranslation,
                           self.currentTranslation?.id == card.id {
                            let persistentTranslation = Translation(
                                id: card.id,
                                sourceText: card.sourceText,
                                translatedText: card.translatedText,
                                timestamp: card.timestamp,
                                sourceType: card.sourceType,
                                sourceImage: card.sourceImage,
                                stickerImage: card.stickerImage
                            )
                            context.insert(persistentTranslation)
                            self.currentTranslation = nil
                        }
                    }
                }
                
                if !total.isEmpty {
                    self.lastResponseTokenCount = (try? chat.sizeInTokens(text: total)) ?? 0
                }
                if let t = chat.getLastResponseGenerationTime() {
                    self.lastResponseLibraryTime = t
                }
                if self.lastResponseLibraryTime > 0 && self.lastResponseTokenCount > 0 {
                    self.lastResponseTokensPerSecond =
                        Double(self.lastResponseTokenCount) / self.lastResponseLibraryTime
                }
                
            } catch is CancellationError {
                NSLog("Processing was cancelled.")
            } catch {
                NSLog("Error during image processing: \(error.localizedDescription)")
            }
        }
    }
    // MARK: - Voice Recording
    func startVoiceRecording() {
        guard !isRecording, let whisper = whisperService else { return }
        do {
            try whisper.startRecording()
            isRecording = true
        } catch {
            micError = "Mic error: \(error.localizedDescription)"
        }
    }
    
    func stopVoiceRecordingAndProcess() {
        guard isRecording,
              let whisper = whisperService,
              let url = whisper.stopRecording()
        else { return }
        
        isRecording = false
        
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self,
                  let whisper = await self.whisperService
            else { return }
            
            do {
                let text = try whisper.transcribeAudio(at: url)
                await MainActor.run {
                    self.processText(text, sourceType: .voice)
                }
            } catch {
                await MainActor.run {
                    self.micError = "Transcription failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - History Management
    func clearHistory() {
        guard let modelContext else { return }
        do {
            // Fetch all translations and delete them.
            try modelContext.delete(model: Translation.self)
            currentTranslation = nil
            expandedTranslationId = nil
        } catch {
            print("Failed to clear history: \(error)")
        }
    }

    func deleteTranslation(id: UUID, context: ModelContext) {
        // We pass the context directly here from the view for simplicity.
        let descriptor = FetchDescriptor<Translation>(
            predicate: #Predicate { $0.id == id }
        )
        if let translationToDelete = try? context.fetch(descriptor).first {
            context.delete(translationToDelete)
        }
        if expandedTranslationId == id {
            expandedTranslationId = nil
        }
    }
}
