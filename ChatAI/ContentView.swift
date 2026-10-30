import SwiftUI
import PhotosUI
import UIKit

// MARK: - Theme

enum AppTheme {
    static let bg         = Color(red: 0.08, green: 0.06, blue: 0.06)
    static let surface    = Color(red: 0.13, green: 0.10, blue: 0.09)
    static let accent     = Color(red: 1.00, green: 0.34, blue: 0.13)   // #FF5721 cam
    static let accentGlow = Color(red: 1.00, green: 0.50, blue: 0.20)
    static let textPri    = Color.white
    static let textSec    = Color(white: 0.65)
    static let divider    = Color(white: 0.20)
    static let userBubble = Color(red: 1.00, green: 0.34, blue: 0.13)
    static let aiBubble   = Color(red: 0.16, green: 0.13, blue: 0.12)
    static let inputBg    = Color(red: 0.16, green: 0.13, blue: 0.12)
}

// MARK: - Root (4 tabs)

struct ContentView: View {
    @StateObject private var viewModel    = ChatViewModel()
    @StateObject private var voiceManager = VoiceManager()
    @StateObject private var historyMgr   = HistoryManager.shared

    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            AppTheme.bg.ignoresSafeArea()

            // Content
            Group {
                switch selectedTab {
                case 0: ChatTabView(viewModel: viewModel, voiceManager: voiceManager)
                case 1: HistoryTabView(viewModel: viewModel)
                case 2: MemoryTabView()
                case 3: SettingsTabView()
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 64)

            // Bottom tab bar
            AppTabBar(selectedTab: $selectedTab)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            viewModel.onSpeakReply = { text, gender in
                let azureKey    = KeychainHelper.read(forKey: "azure_tts_key") ?? ""
                let azureRegion = KeychainHelper.read(forKey: "azure_tts_region") ?? ""
                voiceManager.speak(text: text, gender: gender, azureKey: azureKey, azureRegion: azureRegion)
            }
        }
    }
}

// MARK: - Bottom Tab Bar

struct AppTabBar: View {
    @Binding var selectedTab: Int

    private let items: [(icon: String, label: String)] = [
        ("bubble.left.fill", "Chat"),
        ("clock.fill",       "Lịch sử"),
        ("brain",            "Memory"),
        ("gearshape.fill",   "Cài đặt")
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<4) { i in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedTab = i }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: items[i].icon)
                            .font(.system(size: 20))
                        Text(items[i].label)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(selectedTab == i ? AppTheme.accent : AppTheme.textSec)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(
            AppTheme.surface
                .overlay(AppTheme.divider.frame(height: 0.5), alignment: .top)
        )
        .frame(height: 64)
    }
}

// MARK: - Chat Tab

struct ChatTabView: View {
    @ObservedObject var viewModel: ChatViewModel
    @ObservedObject var voiceManager: VoiceManager

    @State private var showProviderMenu  = false
    @State private var showHistory       = false
    @State private var pendingAttachments: [ChatAttachment] = []
    @State private var showImagePicker   = false
    @State private var showFilePicker    = false
    @State private var imagePickerSource: UIImagePickerController.SourceType = .photoLibrary

    var body: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider().background(AppTheme.divider)
            messageList
            if let err = viewModel.errorMessage { errorBanner(err) }
            if let ve  = voiceManager.voiceErrorMessage { voiceErrorBanner(ve) }
            if voiceManager.isSpeaking { stopSpeakingBar }
            inputBar
        }
        .background(AppTheme.bg)
        .confirmationDialog("Chọn AI", isPresented: $showProviderMenu, titleVisibility: .visible) {
            ForEach(AIProviderKind.allCases) { p in
                Button(p.rawValue) { viewModel.selectedProviderRaw = p.rawValue }
            }
            Button("Hủy", role: .cancel) {}
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(viewModel: viewModel)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(sourceType: imagePickerSource) { img in
                if let att = try? AttachmentService.encode(image: img),
                   pendingAttachments.count < AttachmentService.maxAttachments(viewModel.selectedProvider) {
                    pendingAttachments.append(att)
                }
            }
        }
        .sheet(isPresented: $showFilePicker) {
            DocumentPickerView { url in
                guard let data = try? Data(contentsOf: url) else { return }
                let att = AttachmentService.encode(pdfData: data, fileName: url.lastPathComponent)
                if pendingAttachments.count < AttachmentService.maxAttachments(viewModel.selectedProvider) {
                    pendingAttachments.append(att)
                }
            }
        }
    }

    // ── Header ────────────────────────────────────────────────────────────────
    private var chatHeader: some View {
        HStack(spacing: 10) {
            // Avatar nhỏ
            Image("companion_neutral")
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .overlay(Circle().stroke(AppTheme.accent, lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 1) {
                Text("ChatAI")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(AppTheme.textPri)
                Button {
                    showProviderMenu = true
                } label: {
                    HStack(spacing: 3) {
                        Text(viewModel.selectedProvider.rawValue
                            .components(separatedBy: "(").first?
                            .trimmingCharacters(in: .whitespaces) ?? "")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.accent)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                            .foregroundColor(AppTheme.accent)
                    }
                }
            }

            Spacer()

            // Live call button
            LiveCallButton(viewModel: viewModel)
                .foregroundColor(AppTheme.textSec)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppTheme.bg)
    }

    // ── Message list ──────────────────────────────────────────────────────────
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.messages) { msg in
                        ChatBubble(message: msg).id(msg.id)
                    }
                    if viewModel.isSending {
                        HStack {
                            TypingIndicator()
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 8)
            }
            .background(AppTheme.bg)
            .onChange(of: viewModel.messages) { _ in
                if let last = viewModel.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // ── Error banners ─────────────────────────────────────────────────────────
    private func errorBanner(_ msg: String) -> some View {
        HStack {
            Text(msg).font(.footnote).foregroundColor(.red)
            Spacer()
            Button { UIPasteboard.general.string = msg } label: {
                Image(systemName: "doc.on.doc").foregroundColor(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.08))
    }

    private func voiceErrorBanner(_ msg: String) -> some View {
        Text(msg).font(.footnote).foregroundColor(.orange)
            .padding(.horizontal, 16).padding(.vertical, 4)
    }

    private var stopSpeakingBar: some View {
        Button { voiceManager.stopSpeaking() } label: {
            Label("Dừng đọc", systemImage: "stop.circle.fill")
                .font(.footnote).foregroundColor(AppTheme.accent)
        }
        .padding(.horizontal, 16).padding(.vertical, 4)
    }

    // ── Input bar ─────────────────────────────────────────────────────────────
    private var inputBar: some View {
        let supportsAtt = AttachmentService.supportsAttachments(viewModel.selectedProvider)
        let maxAtt = AttachmentService.maxAttachments(viewModel.selectedProvider)

        return VStack(spacing: 0) {
            // Thumbnail strip
            if !pendingAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pendingAttachments) { att in
                            ZStack(alignment: .topTrailing) {
                                if let img = att.thumbnail {
                                    Image(uiImage: img)
                                        .resizable().scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                } else {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(AppTheme.surface)
                                        .frame(width: 56, height: 56)
                                        .overlay(Image(systemName: "doc.fill").foregroundColor(AppTheme.textSec))
                                }
                                Button {
                                    pendingAttachments.removeAll { $0.id == att.id }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Color.black.opacity(0.5).clipShape(Circle()))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                }
                Divider().background(AppTheme.divider)
            }

            // Row
            HStack(spacing: 10) {
                // Attach +
                if supportsAtt {
                    Menu {
                        Button {
                            imagePickerSource = .photoLibrary
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showImagePicker = true }
                        } label: { Label("Hình ảnh", systemImage: "photo.on.rectangle") }

                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button {
                                imagePickerSource = .camera
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showImagePicker = true }
                            } label: { Label("Chụp ảnh", systemImage: "camera") }
                        }

                        Button {
                            showFilePicker = true
                        } label: { Label("Tệp PDF", systemImage: "doc") }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(pendingAttachments.count >= maxAtt ? AppTheme.textSec : AppTheme.accent)
                    }
                    .disabled(pendingAttachments.count >= maxAtt)
                }

                // TextField
                TextField("Nhập tin nhắn...", text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(AppTheme.inputBg)
                    .cornerRadius(20)
                    .foregroundColor(AppTheme.textPri)
                    .font(.system(size: 15))

                // Mic / Send
                if viewModel.inputText.trimmingCharacters(in: .whitespaces).isEmpty && pendingAttachments.isEmpty {
                    // Mic button
                    Button {
                        let groqKey = KeychainHelper.read(forKey: AIProviderKind.groq.keychainKey) ?? ""
                        if voiceManager.isListening {
                            voiceManager.stopListeningAndTranscribe(groqAPIKey: groqKey) { text in
                                viewModel.inputText = text
                                viewModel.send(attachments: pendingAttachments)
                                pendingAttachments = []
                            }
                        } else {
                            voiceManager.startListening(
                                groqAPIKey: groqKey,
                                onPartialResult: { viewModel.inputText = $0 },
                                onFinish: { text in
                                    viewModel.inputText = text
                                    viewModel.send(attachments: pendingAttachments)
                                    pendingAttachments = []
                                }
                            )
                        }
                    } label: {
                        Image(systemName: voiceManager.isListening ? "mic.fill" : "mic.fill")
                            .font(.system(size: 20))
                            .foregroundColor(voiceManager.isListening ? .red : AppTheme.textSec)
                            .frame(width: 40, height: 40)
                            .background(AppTheme.surface)
                            .clipShape(Circle())
                    }
                } else {
                    // Send button
                    Button {
                        viewModel.send(attachments: pendingAttachments)
                        pendingAttachments = []
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(AppTheme.accent)
                            .clipShape(Circle())
                    }
                    .disabled(viewModel.isSending)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppTheme.bg)
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage
    @State private var copied = false

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            // AI avatar
            if !isUser {
                Image("companion_neutral")
                    .resizable().scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(AppTheme.accent.opacity(0.6), lineWidth: 1))
                    .alignmentGuide(.bottom) { d in d[.bottom] }
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Attachments
                if message.hasAttachments {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(message.attachments) { att in
                                if let img = att.thumbnail {
                                    Image(uiImage: img)
                                        .resizable().scaledToFill()
                                        .frame(width: 120, height: 120)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                } else {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(AppTheme.surface)
                                        .frame(width: 80, height: 80)
                                        .overlay(
                                            VStack(spacing: 4) {
                                                Image(systemName: "doc.fill").font(.title2)
                                                Text(att.fileName).font(.caption2).lineLimit(2)
                                            }.foregroundColor(AppTheme.textSec)
                                        )
                                }
                            }
                        }
                    }
                }

                // Text bubble
                if !message.content.isEmpty && message.content != "(đính kèm)" {
                    Text(message.content)
                        .font(.system(size: 15))
                        .foregroundColor(isUser ? .white : AppTheme.textPri)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isUser ? AppTheme.userBubble : AppTheme.aiBubble)
                        .cornerRadius(isUser ? 18 : 18, antialiased: true)
                        .cornerRadius(isUser ? 4 : 18, antialiased: true)
                }

                // Copy button
                Button {
                    UIPasteboard.general.string = message.content
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2)
                        .foregroundColor(AppTheme.textSec.opacity(0.6))
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}

// MARK: - Typing indicator

struct TypingIndicator: View {
    @State private var phase: Int = 0
    let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(phase == i ? AppTheme.accent : AppTheme.textSec)
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.2 : 0.85)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.aiBubble)
        .cornerRadius(14)
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}

// MARK: - History Tab

struct HistoryTabView: View {
    @ObservedObject var viewModel: ChatViewModel
    @StateObject private var historyMgr = HistoryManager.shared
    @State private var renameSession: ChatSession?
    @State private var newTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Lịch sử chat")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppTheme.textPri)
                Spacer()
                Button {
                    viewModel.startNewChat()
                } label: {
                    Image(systemName: "square.and.pencil")
                        .foregroundColor(AppTheme.accent)
                        .font(.system(size: 18))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(AppTheme.divider)

            if historyMgr.sessions.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.textSec)
                    Text("Chưa có lịch sử chat")
                        .foregroundColor(AppTheme.textSec)
                }
                Spacer()
            } else {
                List {
                    ForEach(historyMgr.sessions) { session in
                        Button {
                            viewModel.load(session: session)
                        } label: {
                            HStack(spacing: 12) {
                                Image("companion_neutral")
                                    .resizable().scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(AppTheme.accent.opacity(0.5), lineWidth: 1))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(session.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(AppTheme.textPri)
                                        .lineLimit(1)
                                    Text(session.preview)
                                        .font(.system(size: 12))
                                        .foregroundColor(AppTheme.textSec)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Text(session.updatedAt, style: .relative)
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textSec)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(AppTheme.surface)
                        .listRowSeparatorTint(AppTheme.divider)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                historyMgr.delete(session: session)
                            } label: { Label("Xóa", systemImage: "trash") }

                            Button {
                                renameSession = session
                                newTitle = session.title
                            } label: {
                                Label("Đổi tên", systemImage: "pencil")
                            }.tint(.orange)
                        }
                    }
                }
                .listStyle(.plain)
                .background(AppTheme.bg)
                .scrollContentBackground(.hidden)
            }
        }
        .background(AppTheme.bg)
        .alert("Đổi tên", isPresented: .init(get: { renameSession != nil }, set: { if !$0 { renameSession = nil } })) {
            TextField("Tên mới", text: $newTitle)
            Button("Lưu") {
                if let s = renameSession { historyMgr.rename(session: s, newTitle: newTitle) }
                renameSession = nil
            }
            Button("Hủy", role: .cancel) { renameSession = nil }
        }
        .onAppear { historyMgr.loadSessions() }
    }
}

// MARK: - Memory Tab

struct MemoryTabView: View {
    @StateObject private var historyMgr = HistoryManager.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Memory")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(AppTheme.textPri)
                    Text("Những điều quan trọng mình luôn nhớ về bạn")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.textSec)
                }
                Spacer()
                Text("\(historyMgr.memories.count)/50")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.textSec)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().background(AppTheme.divider)

            if historyMgr.memories.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "brain")
                        .font(.system(size: 40))
                        .foregroundColor(AppTheme.textSec)
                    Text("Chưa có thông tin nào được ghi nhớ")
                        .foregroundColor(AppTheme.textSec)
                        .multilineTextAlignment(.center)
                    Text("AI sẽ tự động ghi nhớ thông tin quan trọng\ntrong lúc chat")
                        .font(.caption)
                        .foregroundColor(AppTheme.textSec.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                Spacer()
            } else {
                List {
                    ForEach(historyMgr.memories) { item in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(AppTheme.accent)
                                .frame(width: 8, height: 8)
                                .padding(.top, 4)
                                .alignmentGuide(.top) { d in d[.top] }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.content)
                                    .font(.system(size: 14))
                                    .foregroundColor(AppTheme.textPri)
                                Text(item.savedAt, style: .date)
                                    .font(.system(size: 11))
                                    .foregroundColor(AppTheme.textSec)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(AppTheme.surface)
                        .listRowSeparatorTint(AppTheme.divider)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                historyMgr.deleteMemory(item)
                            } label: { Label("Xóa", systemImage: "trash") }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)

                Button(role: .destructive) {
                    historyMgr.clearAllMemory()
                } label: {
                    Text("Xóa tất cả bộ nhớ")
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.vertical, 10)
                }
            }
        }
        .background(AppTheme.bg)
    }
}

// MARK: - Settings Tab

struct SettingsTabView: View {
    @State private var showRobotPreview = false
    @State private var showFullSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    // Profile header
                    HStack(spacing: 14) {
                        Image("companion_neutral")
                            .resizable().scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(AppTheme.accent, lineWidth: 2))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("ChatAI")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(AppTheme.textPri)
                            Text("TP Signature")
                                .font(.system(size: 12))
                                .foregroundColor(AppTheme.accent)
                        }
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(AppTheme.surface)
                }

                Section("Tuỳ chỉnh AI") {
                    NavigationLink {
                        FullSettingsView()
                    } label: {
                        settingsRow(icon: "slider.horizontal.3", label: "Cài đặt đầy đủ")
                    }

                    Button {
                        showRobotPreview = true
                    } label: {
                        settingsRow(icon: "face.smiling", label: "Xem biểu cảm AI Companion")
                    }
                }
                .listRowBackground(AppTheme.surface)

                Section("Thông tin") {
                    HStack {
                        settingsRow(icon: "info.circle", label: "Phiên bản")
                        Spacer()
                        Text("1.0")
                            .font(.system(size: 14))
                            .foregroundColor(AppTheme.textSec)
                    }
                }
                .listRowBackground(AppTheme.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppTheme.bg)
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showRobotPreview) {
            RobotFacePreviewView()
        }
        .background(AppTheme.bg)
    }

    private func settingsRow(icon: String, label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AppTheme.accent)
                .frame(width: 28)
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(AppTheme.textPri)
        }
    }
}

// MARK: - Full Settings (renamed to avoid clash)

struct FullSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var openAIKey:    String = KeychainHelper.read(forKey: AIProviderKind.openAI.keychainKey) ?? ""
    @State private var anthropicKey: String = KeychainHelper.read(forKey: AIProviderKind.anthropic.keychainKey) ?? ""
    @State private var geminiKey:    String = KeychainHelper.read(forKey: AIProviderKind.gemini.keychainKey) ?? ""
    @State private var grokKey:      String = KeychainHelper.read(forKey: AIProviderKind.grok.keychainKey) ?? ""
    @State private var deepseekKey:  String = KeychainHelper.read(forKey: AIProviderKind.deepseek.keychainKey) ?? ""
    @State private var groqKey:      String = KeychainHelper.read(forKey: AIProviderKind.groq.keychainKey) ?? ""
    @State private var azureKey:     String = KeychainHelper.read(forKey: "azure_tts_key") ?? ""
    @State private var azureRegion:  String = KeychainHelper.read(forKey: "azure_tts_region") ?? ""

    @AppStorage("model_openai")    var openAIModel:    String = AIProviderKind.openAI.defaultModel
    @AppStorage("model_anthropic") var anthropicModel: String = AIProviderKind.anthropic.defaultModel
    @AppStorage("model_gemini")    var geminiModel:    String = AIProviderKind.gemini.defaultModel
    @AppStorage("model_grok")      var grokModel:      String = AIProviderKind.grok.defaultModel
    @AppStorage("model_deepseek")  var deepseekModel:  String = AIProviderKind.deepseek.defaultModel
    @AppStorage("model_groq")      var groqModel:      String = AIProviderKind.groq.defaultModel
    @AppStorage("autoSpeakReplies") var autoSpeakReplies: Bool = false
    @AppStorage("voiceGender")     var voiceGenderRaw: String = VoiceGender.female.rawValue
    @AppStorage("autoMemory")      var autoMemory:     Bool = true
    @State private var pickerMode: ModelPickerMode?

    var body: some View {
        Form {
            Section("Giọng nói") {
                Toggle("Tự động đọc to câu trả lời", isOn: $autoSpeakReplies)
                Picker("Giọng đọc", selection: $voiceGenderRaw) {
                    ForEach(VoiceGender.allCases) { g in Text(g.rawValue).tag(g.rawValue) }
                }
            }
            Section("Azure TTS – giọng neural tiếng Việt") {
                SecureField("Azure TTS key", text: $azureKey)
                TextField("Region (vd: southeastasia)", text: $azureRegion)
            }
            Section("AI Memory") {
                Toggle("Tự động ghi nhớ thông tin", isOn: $autoMemory)
            }
            providerSection("ChatGPT (OpenAI)", key: $openAIKey, placeholder: "sk-...", model: $openAIModel, mode: .openai)
            providerSection("Claude (Anthropic)", key: $anthropicKey, placeholder: "sk-ant-...", model: $anthropicModel, mode: .anthropic)
            providerSection("Gemini (Google)", key: $geminiKey, placeholder: "AIza...", model: $geminiModel, mode: .gemini)
            providerSection("Grok (xAI)", key: $grokKey, placeholder: "xai-...", model: $grokModel, mode: .grok)
            providerSection("DeepSeek", key: $deepseekKey, placeholder: "sk-...", model: $deepseekModel, mode: .deepseek)
            providerSection("Groq (Llama – Miễn phí)", key: $groqKey, placeholder: "gsk_...", model: $groqModel, mode: .groq)
        }
        .navigationTitle("Cài đặt đầy đủ")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Xong") {
                    KeychainHelper.save(openAIKey,    forKey: AIProviderKind.openAI.keychainKey)
                    KeychainHelper.save(anthropicKey, forKey: AIProviderKind.anthropic.keychainKey)
                    KeychainHelper.save(geminiKey,    forKey: AIProviderKind.gemini.keychainKey)
                    KeychainHelper.save(grokKey,      forKey: AIProviderKind.grok.keychainKey)
                    KeychainHelper.save(deepseekKey,  forKey: AIProviderKind.deepseek.keychainKey)
                    KeychainHelper.save(groqKey,      forKey: AIProviderKind.groq.keychainKey)
                    KeychainHelper.save(azureKey,     forKey: "azure_tts_key")
                    KeychainHelper.save(azureRegion,  forKey: "azure_tts_region")
                    dismiss()
                }
            }
        }
        .sheet(item: $pickerMode) { mode in
            ModelPickerView(
                title: mode.title,
                currentModel: mode.binding(openAI: $openAIModel, anthropic: $anthropicModel,
                                           gemini: $geminiModel, grok: $grokModel,
                                           deepseek: $deepseekModel, groq: $groqModel),
                fetch: {
                    switch mode {
                    case .openai:    return try await OpenAIModelFetcher.fetchModels(apiKey: openAIKey)
                    case .anthropic: return try await AnthropicModelFetcher.fetchModels(apiKey: anthropicKey)
                    case .gemini:    return try await GeminiModelFetcher.fetchModels(apiKey: geminiKey)
                    case .grok:      return try await GrokModelFetcher.fetchModels(apiKey: grokKey)
                    case .deepseek:  return try await DeepSeekModelFetcher.fetchModels(apiKey: deepseekKey)
                    case .groq:      return try await GroqModelFetcher.fetchModels(apiKey: groqKey)
                    }
                }
            )
        }
    }

    @ViewBuilder
    private func providerSection(_ title: String, key: Binding<String>, placeholder: String,
                                  model: Binding<String>, mode: ModelPickerMode) -> some View {
        Section(title) {
            SecureField(placeholder, text: key)
            HStack {
                Text(model.wrappedValue).font(.footnote).foregroundColor(.secondary).lineLimit(1)
                Spacer()
                Button("Chọn model") { pickerMode = mode }.font(.footnote)
            }
        }
    }
}

// MARK: - Picker wrappers (keep existing ImagePickerView / DocumentPickerView from AttachmentService usage)

struct HistoryView: View {
    @ObservedObject var viewModel: ChatViewModel
    @StateObject private var historyMgr = HistoryManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var renameSession: ChatSession?
    @State private var newTitle = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(historyMgr.sessions) { session in
                    Button {
                        viewModel.load(session: session)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title).font(.headline).foregroundColor(.primary)
                            Text(session.preview).font(.caption).foregroundColor(.secondary).lineLimit(2)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { historyMgr.delete(session: session) } label: {
                            Label("Xóa", systemImage: "trash")
                        }
                        Button {
                            renameSession = session; newTitle = session.title
                        } label: { Label("Đổi tên", systemImage: "pencil") }.tint(.orange)
                    }
                }
            }
            .navigationTitle("Lịch sử chat")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { viewModel.startNewChat(); dismiss() } label: {
                        Label("Chat mới", systemImage: "plus")
                    }
                }
            }
            .alert("Đổi tên", isPresented: .init(get: { renameSession != nil }, set: { if !$0 { renameSession = nil } })) {
                TextField("Tên mới", text: $newTitle)
                Button("Lưu") {
                    if let s = renameSession { historyMgr.rename(session: s, newTitle: newTitle) }
                    renameSession = nil
                }
                Button("Hủy", role: .cancel) { renameSession = nil }
            }
            .onAppear { historyMgr.loadSessions() }
        }
    }
}
