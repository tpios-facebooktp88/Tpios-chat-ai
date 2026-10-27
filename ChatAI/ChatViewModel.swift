import Foundation
import SwiftUI

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isSending: Bool = false
    @Published var errorMessage: String?
    @Published var currentSession: ChatSession?
    @Published var isExtractingMemory: Bool = false

    @AppStorage("selectedProvider") var selectedProviderRaw: String = AIProviderKind.openAI.rawValue
    @AppStorage("model_openai")    var openAIModel:    String = AIProviderKind.openAI.defaultModel
    @AppStorage("model_anthropic") var anthropicModel: String = AIProviderKind.anthropic.defaultModel
    @AppStorage("model_gemini")    var geminiModel:    String = AIProviderKind.gemini.defaultModel
    @AppStorage("model_grok")      var grokModel:      String = AIProviderKind.grok.defaultModel
    @AppStorage("model_deepseek")  var deepseekModel:  String = AIProviderKind.deepseek.defaultModel
    @AppStorage("model_groq")      var groqModel:      String = AIProviderKind.groq.defaultModel
    @AppStorage("autoSpeakReplies") var autoSpeakReplies: Bool = false
    @AppStorage("voiceGender")     var voiceGenderRaw: String = VoiceGender.female.rawValue
    @AppStorage("autoMemory")      var autoMemory: Bool = true

    var voiceGender: VoiceGender { VoiceGender(rawValue: voiceGenderRaw) ?? .female }
    var onSpeakReply: ((String, VoiceGender) -> Void)?
    var selectedProvider: AIProviderKind { AIProviderKind(rawValue: selectedProviderRaw) ?? .openAI }

    private var currentModel: String {
        switch selectedProvider {
        case .openAI:    return openAIModel
        case .anthropic: return anthropicModel
        case .gemini:    return geminiModel
        case .grok:      return grokModel
        case .deepseek:  return deepseekModel
        case .groq:      return groqModel
        }
    }

    private let openAIService   = OpenAICompatibleService(baseURL: URL(string: "https://api.openai.com/v1/chat/completions")!)
    private let grokService     = OpenAICompatibleService(baseURL: URL(string: "https://api.x.ai/v1/chat/completions")!)
    private let deepseekService = OpenAICompatibleService(baseURL: URL(string: "https://api.deepseek.com/chat/completions")!)
    private let groqService     = OpenAICompatibleService(baseURL: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
    private let anthropicService = AnthropicService()
    private let geminiService    = GeminiService()

    func startNewChat() {
        saveCurrentSession()
        messages = []
        errorMessage = nil
        currentSession = nil
    }

    func load(session: ChatSession) {
        saveCurrentSession()
        messages = session.messages
        currentSession = session
        errorMessage = nil
    }

    func saveCurrentSession() {
        guard !messages.isEmpty else { return }
        var session = currentSession ?? ChatSession(
            provider: selectedProvider.rawValue,
            messages: messages
        )
        session.messages = messages
        session.provider = selectedProvider.rawValue
        HistoryManager.shared.save(session: session)
        currentSession = session
    }

    func send(attachments: [ChatAttachment] = []) {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty, !isSending else { return }
        let text = trimmed.isEmpty ? "(đính kèm)" : trimmed
        messages.append(ChatMessage(role: .user, content: text, attachments: attachments))
        inputText = ""
        isSending = true
        errorMessage = nil

        Task {
            do {
                let reply = try await fetchWithRetry()
                messages.append(ChatMessage(role: .assistant, content: reply))
                if autoSpeakReplies { onSpeakReply?(reply, voiceGender) }
                saveCurrentSession()
                if autoMemory {
                    await extractMemory(from: trimmed)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }

    private func extractMemory(from userMessage: String) async {
        let prompt = HistoryManager.extractMemoryPrompt(from: userMessage)
        let key = KeychainHelper.read(forKey: selectedProvider.keychainKey) ?? ""
        guard !key.isEmpty else { return }

        let extractMsg = [ChatMessage(role: .user, content: prompt)]
        do {
            let result: String
            switch selectedProvider {
            case .openAI:    result = try await openAIService.sendMessage(history: extractMsg, apiKey: key, model: openAIModel)
            case .anthropic: result = try await anthropicService.sendMessage(history: extractMsg, apiKey: key, model: anthropicModel)
            case .gemini:    result = try await geminiService.sendMessage(history: extractMsg, apiKey: key, model: geminiModel)
            case .grok:      result = try await grokService.sendMessage(history: extractMsg, apiKey: key, model: grokModel)
            case .deepseek:  result = try await deepseekService.sendMessage(history: extractMsg, apiKey: key, model: deepseekModel)
            case .groq:      result = try await groqService.sendMessage(history: extractMsg, apiKey: key, model: groqModel)
            }
            if result.hasPrefix("MEMORY:") {
                let memory = result.replacingOccurrences(of: "MEMORY:", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                HistoryManager.shared.addMemory(memory)
            }
        } catch { }
    }

    private func fetchWithRetry(maxAttempts: Int = 3) async throws -> String {
        var lastError: Error = AIProviderError.invalidResponse
        for attempt in 1...maxAttempts {
            do { return try await fetchReply() }
            catch AIProviderError.busy(let msg) {
                lastError = AIProviderError.busy(msg)
                if attempt < maxAttempts {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
        throw lastError
    }

    private func fetchReply() async throws -> String {
        let key = KeychainHelper.read(forKey: selectedProvider.keychainKey) ?? ""
        var history = messages
        if let memoryPrompt = HistoryManager.shared.memorySystemPrompt {
            history.insert(ChatMessage(role: .system, content: memoryPrompt), at: 0)
        }
        let lastAtt = messages.last(where: { $0.role == .user })?.attachments ?? []
        switch selectedProvider {
        case .openAI:    return try await openAIService.sendMessage(history: history, apiKey: key, model: openAIModel, attachments: lastAtt)
        case .anthropic: return try await anthropicService.sendMessage(history: history, apiKey: key, model: anthropicModel, attachments: lastAtt)
        case .gemini:    return try await geminiService.sendMessage(history: history, apiKey: key, model: geminiModel, attachments: lastAtt)
        case .grok:      return try await grokService.sendMessage(history: history, apiKey: key, model: grokModel, attachments: lastAtt)
        case .deepseek:  return try await deepseekService.sendMessage(history: history, apiKey: key, model: deepseekModel)
        case .groq:      return try await groqService.sendMessage(history: history, apiKey: key, model: groqModel)
        }
    }

    func clear() {
        startNewChat()
    }
}
