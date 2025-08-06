import Foundation
import SwiftData
import SwiftUI

@MainActor
final class ChatThreadViewModel: ObservableObject {
    let translation: Translation
    
    @Published var messages: [ChatMessage] = []
    @Published var isProcessing: Bool = false
    
    private var chatThread: ChatThread?
    private let modelContext: ModelContext
    private var chatEngine: Chat?

    // FIX: Added properties to hold the correct language names.
    private let sourceLanguageName: String
    private let targetLanguageName: String
    @MainActor
    init(translation: Translation,
         modelContext: ModelContext,
         onDeviceModel: OnDeviceModel?,
         sourceLanguageName: String,
         targetLanguageName: String) {
        self.translation = translation
        self.modelContext = modelContext
        self.sourceLanguageName = sourceLanguageName
        self.targetLanguageName = targetLanguageName
        fetchOrCreateChatThread()
        Task.detached(priority: .userInitiated) { [weak self] in
                guard let self, let odm = onDeviceModel else { return }
                do {
                    let e = try await ChatService.shared.engine(for: odm)
                    await MainActor.run { self.chatEngine = e }
                } catch {
                    // surface error if you wish
                }
            }
        
        
    }
    
    private func fetchOrCreateChatThread() {
        let threadId = translation.id
        var descriptor = FetchDescriptor<ChatThread>(
            predicate: #Predicate { $0.translationId == threadId }
        )
        descriptor.fetchLimit = 1

        do {
            if let existingThread = try modelContext.fetch(descriptor).first {
                self.chatThread = existingThread
                self.messages = existingThread.messages.sorted(by: { $0.timestamp < $1.timestamp })
            } else {
                let newThread = ChatThread(translationId: translation.id)
                self.chatThread = newThread
                modelContext.insert(newThread)
            }
        } catch {
            print("Failed to fetch or create chat thread: \(error)")
        }
    }

    func send(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let chatThread = chatThread, let chatEngine = chatEngine else { return }

        isProcessing = true
        
        let userMessage = ChatMessage(role: .user, text: text, thread: self.chatThread)
        messages.append(userMessage)
        
        // FIX: Use dynamically passed language names instead of placeholders.
        let prompt = PromptBuilder.chatAboutTranslationPrompt(
            sourceText: translation.sourceText,
            primaryTranslation: translation.translatedText.components(separatedBy: .newlines).first ?? "",
            sourceLang: self.sourceLanguageName,
            targetLang: self.targetLanguageName,
            userQuestion: text
        )

        Task {
            var buffer = ""
            var lastFlush = Date()
            do {
                let responseStream = try await chatEngine.sendMessage(prompt)
                
                let assistantMessage = ChatMessage(role: .assistant, text: "", thread: self.chatThread)
                // FIX: Ensure UI and data mutations happen on the Main Actor.
                await MainActor.run {
                    messages.append(assistantMessage)
                }

                for try await partial in responseStream {
                    buffer.append(partial)
                    if Date().timeIntervalSince(lastFlush) > 0.05 {   // ② flush every 50 ms
                        let chunk = buffer; buffer = ""
                        lastFlush = Date()
                        await MainActor.run {
                            if let i = messages.indices.last {
                                messages[i].text += chunk
                            }
                        }
                    }
                }
            } catch {
                let errorMessage = "Error: \(error.localizedDescription)"
                let errorBotMessage = ChatMessage(role: .assistant, text: errorMessage, thread: self.chatThread)
                await MainActor.run {
                    messages.append(errorBotMessage)
                }
            }
            await MainActor.run {
                 isProcessing = false
            }
        }
    }
}
