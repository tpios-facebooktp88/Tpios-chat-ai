import Foundation

enum ChatRole: String, Codable { case user, assistant, system }

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: ChatRole
    var content: String
    let createdAt: Date

    init(id: UUID = UUID(), role: ChatRole, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

enum AIProviderKind: String, CaseIterable, Identifiable, Codable {
    case openAI = "ChatGPT (OpenAI)"
    case anthropic = "Claude (Anthropic)"
    case gemini = "Gemini (Google)"
    case grok = "Grok (xAI)"
    case deepseek = "DeepSeek"
    case groq = "Groq (Miễn phí)"

    var id: String { rawValue }
    var keychainKey: String {
        switch self {
        case .openAI: return "openai_api_key"
        case .anthropic: return "anthropic_api_key"
        case .gemini: return "gemini_api_key"
        case .grok: return "grok_api_key"
        case .deepseek: return "deepseek_api_key"
        case .groq: return "groq_api_key"
        }
    }
    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .anthropic: return "claude-sonnet-4-5"
        case .gemini: return "gemini-flash-latest"
        case .grok: return "grok-2-latest"
        case .deepseek: return "deepseek-chat"
        case .groq: return "llama-3.1-8b-instant"
        }
    }
}

enum VoiceGender: String, CaseIterable, Identifiable, Codable {
    case female = "Nữ"
    case male = "Nam"
    var id: String { rawValue }
}

enum AIProviderError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case server(String)
    case busy(String)
    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Chưa nhập API key cho provider này."
        case .invalidResponse: return "Phản hồi không hợp lệ từ server."
        case .server(let msg): return msg
        case .busy(let msg): return msg
        }
    }
}
