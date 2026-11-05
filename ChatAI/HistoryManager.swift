import Foundation

// MARK: - Chat Session

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

// MARK: - Memory Item

struct MemoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    var content: String
    let savedAt: Date

    init(id: UUID = UUID(), content: String, savedAt: Date = Date()) {
        self.id = id; self.content = content; self.savedAt = savedAt
    }
}

// MARK: - Profile Field (hồ sơ cố định)

struct ProfileField: Identifiable, Codable {
    let id: String
    let icon: String
    let title: String
    var content: String
    let placeholder: String
}

enum UserProfile {
    static let defaultFields: [ProfileField] = [
        ProfileField(id:"name",    icon:"person.fill",      title:"Tên của bạn",      content:"", placeholder:"Anh tên là..."),
        ProfileField(id:"job",     icon:"briefcase.fill",   title:"Công việc / Dự án", content:"", placeholder:"Anh đang làm..."),
        ProfileField(id:"hobby",   icon:"heart.fill",       title:"Sở thích",          content:"", placeholder:"Anh thích..."),
        ProfileField(id:"goal",    icon:"target",           title:"Mục tiêu",           content:"", placeholder:"Mục tiêu của anh là..."),
        ProfileField(id:"address", icon:"bubble.left.fill", title:"Cách xưng hô",      content:"", placeholder:"Em xưng... gọi anh là..."),
        ProfileField(id:"special", icon:"star.fill",        title:"Yêu cầu đặc biệt",  content:"", placeholder:"Cách trả lời hoặc lưu ý riêng..."),
    ]
}

// MARK: - HistoryManager

final class HistoryManager: ObservableObject {
    static let shared = HistoryManager()

    @Published var sessions:  [ChatSession]  = []
    @Published var memories:  [MemoryItem]   = []
    @Published var profile:   [ProfileField] = UserProfile.defaultFields

    private let docsDir:     URL
    private let historyDir:  URL
    private let memoryFile:  URL
    private let profileFile: URL

    private init() {
        docsDir     = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        historyDir  = docsDir.appendingPathComponent("ChatHistory")
        memoryFile  = docsDir.appendingPathComponent("memory.json")
        profileFile = docsDir.appendingPathComponent("profile.json")
        try? FileManager.default.createDirectory(at: historyDir, withIntermediateDirectories: true)
        loadSessions()
        loadMemory()
        loadProfile()
    }

    // ── Sessions ─────────────────────────────────────────────────────────────

    func loadSessions() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: historyDir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        sessions = files.filter { $0.pathExtension == "json" }.compactMap { url -> ChatSession? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(ChatSession.self, from: data)
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save(session: ChatSession) {
        var s = session; s.updatedAt = Date()
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: historyDir.appendingPathComponent("\(s.id.uuidString).json"))
        }
        loadSessions()
    }

    func delete(session: ChatSession) {
        try? FileManager.default.removeItem(at: historyDir.appendingPathComponent("\(session.id.uuidString).json"))
        loadSessions()
    }

    func rename(session: ChatSession, newTitle: String) {
        var s = session; s.title = newTitle; save(session: s)
    }

    func deleteAll() { sessions.forEach { delete(session: $0) } }

    // ── Memory ────────────────────────────────────────────────────────────────

    func loadMemory() {
        guard let data = try? Data(contentsOf: memoryFile) else { return }
        memories = (try? JSONDecoder().decode([MemoryItem].self, from: data)) ?? []
    }

    func saveMemory() {
        if let data = try? JSONEncoder().encode(memories) { try? data.write(to: memoryFile) }
    }

    func addMemory(_ content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        guard !trimmed.isEmpty, memories.count < 50,
              !memories.contains(where: {
                  $0.content.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased() == normalized
              }) else { return }
        memories.append(MemoryItem(content: trimmed))
        saveMemory()
    }

    func updateMemory(_ item: MemoryItem, content: String) {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = memories.firstIndex(where: { $0.id == item.id }) else { return }
        memories[i].content = trimmed
        saveMemory()
    }

    func deleteMemory(_ item: MemoryItem) {
        memories.removeAll { $0.id == item.id }
        saveMemory()
    }

    func clearAllMemory() { memories.removeAll(); saveMemory() }

    // ── Profile ───────────────────────────────────────────────────────────────

    func loadProfile() {
        guard let data = try? Data(contentsOf: profileFile),
              let saved = try? JSONDecoder().decode([ProfileField].self, from: data) else { return }
        var merged = UserProfile.defaultFields
        for i in merged.indices {
            if let found = saved.first(where: { $0.id == merged[i].id }) {
                merged[i].content = found.content
            }
        }
        profile = merged
    }

    func saveProfile() {
        if let data = try? JSONEncoder().encode(profile) { try? data.write(to: profileFile) }
    }

    func updateProfile(id: String, content: String) {
        guard let i = profile.firstIndex(where: { $0.id == id }) else { return }
        profile[i].content = content
        saveProfile()
    }

    // ── System prompts gửi lên API ────────────────────────────────────────────

    var profileSystemPrompt: String? {
        let filled = profile.filter { !$0.content.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !filled.isEmpty else { return nil }
        let lines = filled.map { "- \($0.title): \($0.content)" }.joined(separator: "\n")
        return "Hồ sơ người dùng — AI phải nhớ và tuân theo suốt cuộc trò chuyện:\n\(lines)"
    }

    var memorySystemPrompt: String? {
        // Ghép profile + memory thành 1 prompt
        var parts: [String] = []
        if let p = profileSystemPrompt { parts.append(p) }
        guard !memories.isEmpty else { return parts.isEmpty ? nil : parts.joined(separator: "\n\n") }
        let items = memories.suffix(15).map { "- \($0.content)" }.joined(separator: "\n")
        parts.append("Thông tin AI đã ghi nhớ từ cuộc trò chuyện:\n\(String(items.prefix(3000)))")
        return parts.joined(separator: "\n\n")
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
