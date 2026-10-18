import Foundation

// MARK: - Chat Session (1 cuộc hội thoại)

struct ChatSession: Identifiable, Codable {
    let id: UUID
    var title: String
    var provider: String
    var messages: [ChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String = "", provider: String, messages: [ChatMessage] = [], createdAt: Date = Date()) {
        self.id = id
        self.title = title.isEmpty ? ChatSession.defaultTitle() : title
        self.provider = provider
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    static func defaultTitle() -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return "Chat \(f.string(from: Date()))"
    }

    var preview: String {
        messages.last?.content.prefix(60).description ?? "Chưa có tin nhắn"
    }
}

// MARK: - Memory Item (thông tin AI ghi nhớ)

struct MemoryItem: Identifiable, Codable {
    let id: UUID
    var content: String
    let savedAt: Date

    init(id: UUID = UUID(), content: String, savedAt: Date = Date()) {
        self.id = id
        self.content = content
        self.savedAt = savedAt
    }
}

// MARK: - HistoryManager

final class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published var sessions: [ChatSession] = []
    @Published var memories: [MemoryItem] = []

    private let docsDir: URL
    private let historyDir: URL
    private let memoryFile: URL

    private init() {
        docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        historyDir = docsDir.appendingPathComponent("ChatHistory")
        memoryFile = docsDir.appendingPathComponent("memory.json")
        try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
        loadSessions()
        loadMemory()
    }

    func loadSessions() {
        let files = (try? FileManager.default.contentsOfDirectory(at: historyDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        sessions = files.filter { $0.pathExtension == "json" }.compactMap { url -> ChatSession? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(ChatSession.self, from: data)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(session: ChatSession) {
        var s = session
        s.updatedAt = Date()
        if let data = try? JSONEncoder().encode(s) {
            let url = historyDir.appendingPathComponent("\(s.id.uuidString).json")
            try? data.write(to: url)
        }
        loadSessions()
    }

    func delete(session: ChatSession) {
        let url = historyDir.appendingPathComponent("\(session.id.uuidString).json")
        try? FileManager.default.removeItem(at: url)
        loadSessions()
    }

    func rename(session: ChatSession, newTitle: String) {
        var s = session
        s.title = newTitle
        save(session: s)
    }

    func deleteAll() { sessions.forEach { delete(session: $0) } }

    func loadMemory() {
        guard let data = try? Data(contentsOf: memoryFile) else { return }
        memories = (try? JSONDecoder().decode([MemoryItem].self, from: data)) ?? []
    }

    func saveMemory() {
        if let data = try? JSONEncoder().encode(memories) { try? data.write(to: memoryFile) }
    }

    func addMemory(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !memories.contains(where: { $0.content == trimmed }) else { return }
        memories.append(MemoryItem(content: trimmed))
        if memories.count > 50 { memories.removeFirst() }
        saveMemory()
    }

    func deleteMemory(_ item: MemoryItem) {
        memories.removeAll { $0.id == item.id }
        saveMemory()
    }

    func clearAllMemory() {
        memories.removeAll()
        saveMemory()
    }

    var memorySystemPrompt: String? {
        guard !memories.isEmpty else { return nil }
        let items = memories.map { "- \($0.content)" }.joined(separator: "\n")
        return "Đây là thông tin quan trọng bạn đã ghi nhớ về người dùng:\n\(items)\n\nHãy sử dụng thông tin này khi phù hợp trong cuộc trò chuyện."
    }

    static func extractMemoryPrompt(from message: String) -> String {
        return """
        Đọc tin nhắn sau và trích xuất thông tin quan trọng cần ghi nhớ về người dùng (tên, nghề nghiệp, sở thích, yêu cầu đặc biệt, thông tin cá nhân quan trọng...).
        Nếu có thông tin cần ghi nhớ, trả về ĐÚNG FORMAT: MEMORY: <nội dung cần nhớ>
        Nếu không có thông tin cần ghi nhớ, trả về: NONE
        Chỉ trả về 1 dòng duy nhất, không giải thích thêm.

        Tin nhắn: "\(message)"
        """
    }
}
