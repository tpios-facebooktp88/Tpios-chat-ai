import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var voiceManager = VoiceManager()
    @StateObject private var historyManager = HistoryManager.shared
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showProviderMenu = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message).id(message.id)
                        }
                        if viewModel.isSending {
                            HStack {
                                ProgressView()
                                Text("Đang trả lời...")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages) { _ in
                    if let last = viewModel.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            if let error = viewModel.errorMessage {
                HStack {
                    Text(error)
                        .font(.footnote)
                        .foregroundColor(.red)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = error
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(.red)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }

            if let voiceError = voiceManager.voiceErrorMessage {
                Text(voiceError)
                    .font(.footnote)
                    .foregroundColor(.orange)
                    .padding(.horizontal)
            }

            if voiceManager.isSpeaking {
                Button { voiceManager.stopSpeaking() } label: {
                    Label("Dừng đọc", systemImage: "stop.circle.fill")
                        .font(.footnote)
                }
                .padding(.horizontal)
            }

            inputBar
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showHistory) { HistoryView(viewModel: viewModel) }
        .onAppear {
            viewModel.onSpeakReply = { text, gender in
                let azureKey    = KeychainHelper.read(forKey: "azure_tts_key") ?? ""
                let azureRegion = KeychainHelper.read(forKey: "azure_tts_region") ?? ""
                voiceManager.speak(text: text, gender: gender, azureKey: azureKey, azureRegion: azureRegion)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            HStack {
                Button { showHistory = true } label: {
                    Image(systemName: "clock.arrow.circlepath").font(.title3)
                }
                .padding(.leading)
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(.title3)
                }
                .padding(.trailing)
            }

            HStack(spacing: 4) {
                Text("AI")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button {
                    showProviderMenu = true
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.selectedProvider.rawValue
                            .components(separatedBy: "(").first?
                            .trimmingCharacters(in: .whitespaces) ?? "")
                            .font(.headline)
                        Image(systemName: "chevron.down").font(.caption)
                    }
                }
                .confirmationDialog("Chọn AI", isPresented: $showProviderMenu, titleVisibility: .visible) {
                    ForEach(AIProviderKind.allCases) { provider in
                        Button(provider.rawValue) {
                            viewModel.selectedProviderRaw = provider.rawValue
                        }
                    }
                    Button("Hủy", role: .cancel) {}
                }
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack {
            Button {
                let groqKey = KeychainHelper.read(forKey: AIProviderKind.groq.keychainKey) ?? ""
                voiceManager.startListening(
                    groqAPIKey: groqKey,
                    onPartialResult: { viewModel.inputText = $0 },
                    onFinish: { text in
                        viewModel.inputText = text
                        viewModel.send()
                    }
                )
            } label: {
                Image(systemName: voiceManager.isListening ? "mic.fill" : "mic")
                    .foregroundColor(voiceManager.isListening ? .red : .accentColor)
            }

            TextField("Nhập tin nhắn hoặc nhấn mic...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)

            Button { viewModel.send() } label: {
                Image(systemName: "paperplane.fill")
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSending)
        }
        .padding()
    }
}

// MARK: - MessageBubble

struct MessageBubble: View {
    let message: ChatMessage
    @State private var copied = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if message.role == .user { Spacer(minLength: 40) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(10)
                    .background(message.role == .user
                        ? Color.blue.opacity(0.85)
                        : Color(.secondarySystemBackground))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(12)

                Button {
                    UIPasteboard.general.string = message.content
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Đã copy" : "Copy",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if message.role == .assistant { Spacer(minLength: 40) }
        }
    }
}

// MARK: - HistoryView

struct HistoryView: View {
    @ObservedObject var viewModel: ChatViewModel
    @StateObject private var historyManager = HistoryManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showMemory = false
    @State private var renameSession: ChatSession?
    @State private var newTitle = ""

    var body: some View {
        NavigationStack {
            List {
                if !historyManager.sessions.isEmpty {
                    Section("Cuộc hội thoại") {
                        ForEach(historyManager.sessions) { session in
                            Button {
                                viewModel.load(session: session)
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text(session.preview)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                    Text(session.provider)
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    historyManager.delete(session: session)
                                } label: {
                                    Label("Xóa", systemImage: "trash")
                                }
                                Button {
                                    renameSession = session
                                    newTitle = session.title
                                } label: {
                                    Label("Đổi tên", systemImage: "pencil")
                                }
                                .tint(.orange)
                            }
                        }
                    }
                } else {
                    Text("Chưa có cuộc hội thoại nào.")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Lịch sử chat")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        viewModel.startNewChat()
                        dismiss()
                    } label: {
                        Label("Chat mới", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button { showMemory = true } label: {
                            Image(systemName: "brain")
                        }
                        if !historyManager.sessions.isEmpty {
                            Button(role: .destructive) {
                                historyManager.deleteAll()
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showMemory) { MemoryView() }
            .alert("Đổi tên cuộc chat", isPresented: .init(
                get: { renameSession != nil },
                set: { if !$0 { renameSession = nil } }
            )) {
                TextField("Tên mới", text: $newTitle)
                Button("Lưu") {
                    if let session = renameSession {
                        historyManager.rename(session: session, newTitle: newTitle)
                    }
                    renameSession = nil
                }
                Button("Hủy", role: .cancel) { renameSession = nil }
            }
            .onAppear { historyManager.loadSessions() }
        }
    }
}

// MARK: - MemoryView

struct MemoryView: View {
    @StateObject private var historyManager = HistoryManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if historyManager.memories.isEmpty {
                    Text("Chưa có thông tin nào được ghi nhớ.\nAI sẽ tự động ghi nhớ thông tin quan trọng trong lúc chat.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(historyManager.memories) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.content)
                            Text(item.savedAt, style: .date)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                historyManager.deleteMemory(item)
                            } label: {
                                Label("Xóa", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("AI Memory")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !historyManager.memories.isEmpty {
                        Button(role: .destructive) {
                            historyManager.clearAllMemory()
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Đóng") { dismiss() }
                }
            }
        }
    }
}
