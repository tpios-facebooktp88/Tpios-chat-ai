import Foundation
import Security

// MARK: - API Services

struct OpenAICompatibleService {
    let baseURL: URL
    func sendMessage(history: [ChatMessage], apiKey: String, model: String, attachments: [ChatAttachment] = []) async throws -> String {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let messages: [[String: Any]] = history.map { msg in
            if msg == history.last(where: { $0.role == .user }), !attachments.isEmpty {
                return ["role": msg.role.rawValue, "content": AttachmentService.openAIContent(text: msg.content, attachments: attachments)]
            }
            return ["role": msg.role.rawValue, "content": msg.content as Any]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": messages])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "unknown error"
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 503 { throw AIProviderError.busy(text) }
            throw AIProviderError.server(text)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let choices = json["choices"] as? [[String: Any]], let msg = choices.first?["message"] as? [String: Any], let content = msg["content"] as? String else { throw AIProviderError.invalidResponse }
        return content
    }
}

struct AnthropicService {
    func sendMessage(history: [ChatMessage], apiKey: String, model: String, attachments: [ChatAttachment] = []) async throws -> String {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let lastUserAnt = history.filter({ $0.role != .system }).last(where: { $0.role == .user })
        let messages: [[String: Any]] = history.filter { $0.role != .system }.map { msg -> [String: Any] in
            if msg == lastUserAnt, !attachments.isEmpty {
                return ["role": "user", "content": AttachmentService.anthropicContent(text: msg.content, attachments: attachments)]
            }
            return ["role": msg.role == .assistant ? "assistant" : "user", "content": msg.content]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "max_tokens": 1024, "messages": messages])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "unknown error"
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 503 || code == 529 { throw AIProviderError.busy(text) }
            throw AIProviderError.server(text)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let content = json["content"] as? [[String: Any]], let text = content.first?["text"] as? String else { throw AIProviderError.invalidResponse }
        return text
    }
}

struct GeminiService {
    func sendMessage(history: [ChatMessage], apiKey: String, model: String, attachments: [ChatAttachment] = []) async throws -> String {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw AIProviderError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let lastUserGem = history.filter({ $0.role != .system }).last(where: { $0.role == .user })
        let contents: [[String: Any]] = history.filter { $0.role != .system }.map { m -> [String: Any] in
            if m == lastUserGem, !attachments.isEmpty {
                return ["role": "user", "parts": AttachmentService.geminiParts(text: m.content, attachments: attachments)]
            }
            return ["role": m.role == .assistant ? "model" : "user", "parts": [["text": m.content]]]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["contents": contents])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let text = String(data: data, encoding: .utf8) ?? "unknown error"
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 503 { throw AIProviderError.busy(text) }
            throw AIProviderError.server(text)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let candidates = json["candidates"] as? [[String: Any]], let content = candidates.first?["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]], let text = parts.first?["text"] as? String else { throw AIProviderError.invalidResponse }
        return text
    }
}

enum GroqModelFetcher {
    static func fetchModels(apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        var request = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIProviderError.server(String(data: data, encoding: .utf8) ?? "unknown error") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let list = json["data"] as? [[String: Any]] else { throw AIProviderError.invalidResponse }
        let excluded = ["whisper", "tts", "guard", "stt", "audio", "moderation", "playai"]
        return list.compactMap { item -> String? in
            guard let id = item["id"] as? String else { return nil }
            let lower = id.lowercased()
            if excluded.contains(where: { lower.contains($0) }) { return nil }
            if let active = item["active"] as? Bool, !active { return nil }
            return id
        }.sorted()
    }
}

enum GeminiModelFetcher {
    static func fetchModels(apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)"
        guard let url = URL(string: urlString) else { throw AIProviderError.invalidResponse }
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw AIProviderError.server(String(data: data, encoding: .utf8) ?? "unknown error") }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let list = json["models"] as? [[String: Any]] else { throw AIProviderError.invalidResponse }
        return list.compactMap { item -> String? in
            guard let methods = item["supportedGenerationMethods"] as? [String], methods.contains("generateContent"), let name = item["name"] as? String else { return nil }
            return name.replacingOccurrences(of: "models/", with: "")
        }.sorted()
    }
}
enum OpenAIModelFetcher {
    static func fetchModels(apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIProviderError.server(String(data: data, encoding: .utf8) ?? "unknown error")
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list = json["data"] as? [[String: Any]]
        else { throw AIProviderError.invalidResponse }
        // Chỉ lấy model chat (gpt-*)
        return list
            .compactMap { $0["id"] as? String }
            .filter { $0.hasPrefix("gpt-") || $0.hasPrefix("o1") || $0.hasPrefix("o3") }
            .sorted()
    }
}

enum AnthropicModelFetcher {
    static func fetchModels(apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIProviderError.server(String(data: data, encoding: .utf8) ?? "unknown error")
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list = json["data"] as? [[String: Any]]
        else { throw AIProviderError.invalidResponse }
        return list.compactMap { $0["id"] as? String }.sorted()
    }
}

enum GrokModelFetcher {
    static func fetchModels(apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        var request = URLRequest(url: URL(string: "https://api.x.ai/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIProviderError.server(String(data: data, encoding: .utf8) ?? "unknown error")
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list = json["data"] as? [[String: Any]]
        else { throw AIProviderError.invalidResponse }
        return list.compactMap { $0["id"] as? String }.sorted()
    }
}

enum DeepSeekModelFetcher {
    static func fetchModels(apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIProviderError.server(String(data: data, encoding: .utf8) ?? "unknown error")
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list = json["data"] as? [[String: Any]]
        else { throw AIProviderError.invalidResponse }
        return list.compactMap { $0["id"] as? String }.sorted()
    }
}

enum KeychainHelper {
    static func save(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }
    static func read(forKey key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
