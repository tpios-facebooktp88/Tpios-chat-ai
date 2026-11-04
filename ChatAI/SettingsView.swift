import SwiftUI
import PhotosUI

// ─────────────────────────────────────────────────────────────────────────────
//  SettingsView.swift  — tab Cài đặt + tất cả màn hình con
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Settings Tab Root

struct SettingsTabView: View {
    @EnvironmentObject var theme: ThemeManager
    @StateObject private var histMgr = HistoryManager.shared
    @State private var showAPIKeys   = false
    @State private var showCompanion = false

    var body: some View {
        NavigationStack {
            ZStack {
                theme.bg.ignoresSafeArea()
                if let wall = theme.wallImage {
                    Image(uiImage: wall).resizable().scaledToFill().ignoresSafeArea()
                        .saturation(ThemeManager.shared.wallSat)
                        .brightness(ThemeManager.shared.wallBri - 1.0)
                        .overlay(Color.black.opacity(ThemeManager.shared.wallOvl))
                }
                List {
                    // ── Header ────────────────────────────────────────
                    Section {
                        HStack(spacing: 14) {
                            if let img = UIImage(named: "companion_neutral") {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(theme.accent, lineWidth: 2))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("ChatAI")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(theme.textPri)
                                Text("Design By Trương Phong")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(theme.accent)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(theme.surface)

                    // ── Tuỳ chỉnh AI ─────────────────────────────────
                    Section {
                        NavigationLink { VoiceRoleSettingsView() } label: {
                            settingsRow("waveform",       "Giọng nói & Vai trò")
                        }
                        NavigationLink { ModelAISettingsView() } label: {
                            settingsRow("cpu",             "Model AI & API Keys")
                        }
                        Button { showCompanion = true } label: {
                            settingsRow("face.smiling",   "AI Companion")
                        }
                    } header: { sectionHeader("slider.horizontal.3", "TUỲ CHỈNH AI") }
                    .listRowBackground(theme.surface)

                    // ── Giao diện ─────────────────────────────────────
                    Section {
                        NavigationLink { ThemeSettingsView() } label: {
                            settingsRow("paintpalette",   "Chủ đề & Màu sắc")
                        }
                    } header: { sectionHeader("paintbrush", "GIAO DIỆN") }
                    .listRowBackground(theme.surface)

                    // ── Tài khoản ─────────────────────────────────────
                    Section {
                        HStack {
                            settingsRow("brain", "AI Memory")
                            Spacer()
                            Text("\(histMgr.memories.count)/50")
                                .font(.system(size: 12))
                                .foregroundColor(theme.textSec)
                        }
                        NavigationLink { HistoryListView() } label: {
                            settingsRow("clock", "Lịch sử chat")
                        }
                    } header: { sectionHeader("person.crop.circle", "TÀI KHOẢN") }
                    .listRowBackground(theme.surface)

                    // ── Thông tin ─────────────────────────────────────
                    Section {
                        HStack {
                            settingsRow("info.circle", "Phiên bản")
                            Spacer()
                            Text("1.0").font(.system(size: 13)).foregroundColor(theme.textSec)
                        }
                    }
                    .listRowBackground(theme.surface)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Cài đặt")
            .toolbarBackground(theme.bg, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showAPIKeys)   { SettingsView() }
        .sheet(isPresented: $showCompanion) { RobotFacePreviewView() }
    }

    private func settingsRow(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(theme.accent)
                .frame(width: 28)
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(theme.textPri)
        }
    }

    private func sectionHeader(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11)).foregroundColor(theme.accent)
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundColor(theme.accent)
        }
    }
}

// MARK: - Giọng nói & Vai trò (kết hợp cài đặt Gemini Live)

struct VoiceRoleSettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @AppStorage("autoSpeakReplies") var autoSpeak: Bool    = false
    @AppStorage("voiceGender")      var voiceGender: String = VoiceGender.female.rawValue
    @AppStorage("live_voice")       var liveVoice: String   = "Zephyr"
    @AppStorage("live_persona")     var persona: String     = LivePersona.defaultText
    @AppStorage("live_barge_in")    var bargeIn: Bool       = false

    // Keyboard dismiss + scroll-to-editor
    @FocusState private var editorFocused: Bool

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            if let wall = theme.wallImage {
                Image(uiImage: wall).resizable().scaledToFill().ignoresSafeArea()
                    .saturation(theme.wallSat)
                    .brightness(theme.wallBri - 1.0)
                    .overlay(Color.black.opacity(theme.wallOvl))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── TTS ───────────────────────────────────────────
                    sectionHeader("GIỌNG NÓI TTS")
                    VStack(spacing: 0) {
                        Toggle("Tự động đọc to câu trả lời", isOn: $autoSpeak)
                            .tint(theme.accent).padding()
                        Divider().background(theme.divider)
                        Picker("Giọng đọc TTS", selection: $voiceGender) {
                            ForEach(VoiceGender.allCases) { g in Text(g.rawValue).tag(g.rawValue) }
                        }
                        .pickerStyle(.menu)
                        .foregroundColor(theme.textPri)
                        .padding()
                    }
                    .background(theme.surface).cornerRadius(14).padding(.horizontal)

                    // ── Gemini Live ───────────────────────────────────
                    sectionHeader("GEMINI LIVE – GIỌNG NÓI")
                    VStack(spacing: 0) {
                        Picker("Giọng Gemini Live", selection: $liveVoice) {
                            ForEach(LiveVoices.all) { v in
                                Text("\(v.id) – \(v.hint)").tag(v.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .foregroundColor(theme.textPri)
                        .padding()
                        Divider().background(theme.divider)
                        Toggle("Cho phép ngắt lời (dùng tai nghe)", isOn: $bargeIn)
                            .tint(theme.accent).padding()
                    }
                    .background(theme.surface).cornerRadius(14).padding(.horizontal)
                    Text("Chọn giọng và chế độ ngắt lời cho màn hình AI Voice")
                        .font(.caption).foregroundColor(theme.textSec)
                        .padding(.horizontal, 20).padding(.bottom, 8)

                    // ── Vai diễn preset ───────────────────────────────
                    sectionHeader("VAI DIỄN AI")
                    VStack(spacing: 0) {
                        ForEach(Array(LivePersona.presets.enumerated()), id: \.element.id) { idx, preset in
                            Button {
                                persona = preset.text
                                editorFocused = false
                            } label: {
                                HStack {
                                    Text(preset.id)
                                        .foregroundColor(persona == preset.text ? theme.accent : theme.textPri)
                                    Spacer()
                                    if persona == preset.text {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(theme.accent)
                                    }
                                }
                                .padding()
                            }
                            if idx < LivePersona.presets.count - 1 {
                                Divider().background(theme.divider)
                            }
                        }
                    }
                    .background(theme.surface).cornerRadius(14).padding(.horizontal)

                    // ── Tuỳ chỉnh vai diễn (không dùng TextEditor trong Form) ──
                    sectionHeader("NỘI DUNG VAI DIỄN")
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nội dung được lưu tự động và dùng cho cả chat chữ lẫn gọi thoại")
                            .font(.caption).foregroundColor(theme.textSec)

                        TextEditor(text: $persona)
                            .focused($editorFocused)
                            .frame(minHeight: 160)
                            .font(.system(size: 14))
                            .foregroundColor(theme.textPri)
                            .scrollContentBackground(.hidden)
                            .background(theme.bg)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(editorFocused ? theme.accent : theme.divider, lineWidth: 1.5)
                            )

                        // Nút ẩn bàn phím + xác nhận lưu
                        if editorFocused {
                            Button {
                                editorFocused = false
                            } label: {
                                Label("Xong — đã lưu", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(theme.accent)
                                    .cornerRadius(10)
                            }
                        }
                    }
                    .padding()
                    .background(theme.surface).cornerRadius(14)
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                }
                .padding(.top, 16)
            }
            // Chạm ngoài editor thì ẩn bàn phím
            .onTapGesture { editorFocused = false }
        }
        .navigationTitle("Giọng nói & Vai trò")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Xong") { editorFocused = false }
                    .foregroundColor(theme.accent)
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(theme.accent)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 6)
    }
}

// MARK: - Model AI & API Keys

struct ModelAISettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @AppStorage("selected_provider") var selectedProviderRaw: String = AIProviderKind.gemini.rawValue
    @AppStorage("model_openai")    var openAIModel:    String = AIProviderKind.openAI.defaultModel
    @AppStorage("model_anthropic") var anthropicModel: String = AIProviderKind.anthropic.defaultModel
    @AppStorage("model_gemini")    var geminiModel:    String = AIProviderKind.gemini.defaultModel
    @AppStorage("model_grok")      var grokModel:      String = AIProviderKind.grok.defaultModel
    @AppStorage("model_deepseek")  var deepseekModel:  String = AIProviderKind.deepseek.defaultModel
    @AppStorage("model_groq")      var groqModel:      String = AIProviderKind.groq.defaultModel

    @State private var keys: [AIProviderKind: String] = {
        var d: [AIProviderKind: String] = [:]
        for p in AIProviderKind.allCases { d[p] = KeychainHelper.read(forKey: p.keychainKey) ?? "" }
        return d
    }()
    @State private var pickerMode: ModelPickerMode?
    @State private var saved = false

    private let providers: [(AIProviderKind, String, String)] = [
        (.openAI,    "ChatGPT",   "Trò chuyện · Đa năng · Sáng tạo"),
        (.anthropic, "Claude",    "An toàn · Logic · Phân tích"),
        (.gemini,    "Gemini",    "Đa phương thức · Kết nối Google"),
        (.grok,      "Grok",      "Nhanh · Thời sự · Sáng tạo"),
        (.deepseek,  "DeepSeek",  "Lý luận · Code · Phân tích"),
        (.groq,      "Groq",      "Miễn phí · Nhanh · Linh hoạt"),
    ]

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            if let wall = theme.wallImage {
                Image(uiImage: wall).resizable().scaledToFill().ignoresSafeArea()
                    .saturation(theme.wallSat)
                    .brightness(theme.wallBri - 1.0)
                    .overlay(Color.black.opacity(theme.wallOvl))
            }
            Form {
                Section {
                    ForEach(providers, id: \.0) { (kind, name, desc) in
                        VStack(alignment: .leading, spacing: 8) {
                            // Provider row
                            Button {
                                withAnimation { selectedProviderRaw = kind.rawValue }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "cpu")
                                        .foregroundColor(selectedProviderRaw == kind.rawValue ? theme.accent : theme.textSec)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name).font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(theme.textPri)
                                        Text(desc).font(.system(size: 11))
                                            .foregroundColor(theme.textSec)
                                    }
                                    Spacer()
                                    if selectedProviderRaw == kind.rawValue {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(theme.accent)
                                    } else {
                                        Circle().stroke(theme.textSec, lineWidth: 1.5)
                                            .frame(width: 22, height: 22)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            // API key + model picker (inline)
                            if selectedProviderRaw == kind.rawValue {
                                Divider().background(theme.divider)
                                HStack(spacing: 8) {
                                    Image(systemName: "key.horizontal")
                                        .font(.system(size: 13))
                                        .foregroundColor(theme.textSec)
                                    SecureField(placeholderFor(kind), text: keyBinding(kind))
                                        .font(.system(size: 13))
                                        .foregroundColor(theme.textPri)
                                }
                                HStack {
                                    Text(modelFor(kind))
                                        .font(.system(size: 12))
                                        .foregroundColor(theme.textSec)
                                        .lineLimit(1)
                                    Spacer()
                                    Button("Tải model") { pickerMode = modeFor(kind) }
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(theme.accent)
                                }
                                Button("Lưu key") {
                                    KeychainHelper.save(keys[kind] ?? "", forKey: kind.keychainKey)
                                    saved = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { saved = false }
                                }
                                .font(.system(size: 13))
                                .foregroundColor(saved ? .green : theme.accent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("MÔ HÌNH AI").foregroundColor(theme.accent)
                }
                .listRowBackground(theme.surface)

                Section {
                    Text("API key được lưu trong Keychain của máy và chỉ dùng với provider tương ứng.")
                        .font(.footnote).foregroundColor(theme.textSec)
                }
                .listRowBackground(theme.surface)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Model AI & API Keys")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(item: $pickerMode) { mode in
            ModelPickerView(
                title: mode.title,
                currentModel: mode.binding(
                    openAI: $openAIModel, anthropic: $anthropicModel,
                    gemini: $geminiModel, grok: $grokModel,
                    deepseek: $deepseekModel, groq: $groqModel),
                fetch: {
                    let k = keys[kindFor(mode)] ?? ""
                    switch mode {
                    case .openai:    return try await OpenAIModelFetcher.fetchModels(apiKey: k)
                    case .anthropic: return try await AnthropicModelFetcher.fetchModels(apiKey: k)
                    case .gemini:    return try await GeminiModelFetcher.fetchModels(apiKey: k)
                    case .grok:      return try await GrokModelFetcher.fetchModels(apiKey: k)
                    case .deepseek:  return try await DeepSeekModelFetcher.fetchModels(apiKey: k)
                    case .groq:      return try await GroqModelFetcher.fetchModels(apiKey: k)
                    }
                }
            )
        }
    }

    private func placeholderFor(_ k: AIProviderKind) -> String {
        switch k {
        case .openAI: return "sk-..."
        case .anthropic: return "sk-ant-..."
        case .gemini: return "AIza..."
        case .grok: return "xai-..."
        default: return "key..."
        }
    }
    private func keyBinding(_ kind: AIProviderKind) -> Binding<String> {
        Binding(get: { keys[kind] ?? "" }, set: { keys[kind] = $0 })
    }
    private func modelFor(_ kind: AIProviderKind) -> String {
        switch kind {
        case .openAI: return openAIModel; case .anthropic: return anthropicModel
        case .gemini: return geminiModel; case .grok: return grokModel
        case .deepseek: return deepseekModel; case .groq: return groqModel
        }
    }
    private func modeFor(_ kind: AIProviderKind) -> ModelPickerMode {
        switch kind {
        case .openAI: return .openai; case .anthropic: return .anthropic
        case .gemini: return .gemini; case .grok: return .grok
        case .deepseek: return .deepseek; case .groq: return .groq
        }
    }
    private func kindFor(_ mode: ModelPickerMode) -> AIProviderKind {
        switch mode {
        case .openai: return .openAI; case .anthropic: return .anthropic
        case .gemini: return .gemini; case .grok: return .grok
        case .deepseek: return .deepseek; case .groq: return .groq
        }
    }
}

// MARK: - Chủ đề & Màu sắc

struct ThemeSettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @State private var showPicker  = false
    @State private var pickerR: Double = 1; @State private var pickerG: Double = 0.34; @State private var pickerB: Double = 0.13
    @State private var wallImage: UIImage? = nil
    @State private var showImagePicker = false

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            if let wall = theme.wallImage {
                Image(uiImage: wall).resizable().scaledToFill().ignoresSafeArea()
                    .saturation(theme.wallSat)
                    .brightness(theme.wallBri - 1.0)
                    .overlay(Color.black.opacity(theme.wallOvl))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    segmentHeader("Chủ đề giao diện")

                    // 4 preset
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(appThemePresets) { preset in
                            Button { theme.apply(preset: preset) } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    ZStack(alignment: .topTrailing) {
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(LinearGradient(colors: preset.gradient,
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(height: 80)
                                            .overlay(
                                                VStack(alignment: .leading, spacing: 5) {
                                                    Spacer()
                                                    Capsule().fill(.white.opacity(0.55)).frame(width: 50, height: 5)
                                                    Capsule().fill(.white.opacity(0.30)).frame(width: 35, height: 4)
                                                    Spacer().frame(height: 8)
                                                }.padding(.horizontal, 10)
                                            )
                                        if theme.presetID == preset.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(theme.accent)
                                                .background(Color.white.clipShape(Circle()))
                                                .padding(6)
                                        }
                                    }
                                    Text(preset.name).font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(theme.textPri)
                                    Text(preset.desc).font(.system(size: 11))
                                        .foregroundColor(theme.textSec)
                                }
                            }
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(theme.presetID == preset.id ? theme.accent : Color.clear, lineWidth: 2))
                        }
                    }
                    .padding(.horizontal)

                    dividerLine

                    // 24 màu accent
                    segmentHeader("Màu sắc")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                        ForEach(Array(accentPalette.enumerated()), id: \.offset) { _, rgb in
                            let c = Color(red: rgb.0, green: rgb.1, blue: rgb.2)
                            Button { theme.apply(accent: c) } label: {
                                Circle().fill(c).frame(width: 40, height: 40)
                                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                                    .overlay(
                                        Circle().stroke(Color.white, lineWidth: 2)
                                            .opacity(isCurrentAccent(rgb) ? 1 : 0)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Phối màu tự chọn
                    segmentHeader("Tự phối màu")
                    VStack(spacing: 10) {
                        colorSlider("Đỏ",   value: $pickerR, color: .red)
                        colorSlider("Xanh lá", value: $pickerG, color: .green)
                        colorSlider("Xanh dương", value: $pickerB, color: .blue)
                        Button {
                            theme.apply(accent: Color(red: pickerR, green: pickerG, blue: pickerB))
                        } label: {
                            HStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(red: pickerR, green: pickerG, blue: pickerB))
                                    .frame(width: 36, height: 36)
                                Text("Áp dụng màu này").font(.system(size: 15, weight: .medium))
                                    .foregroundColor(theme.textPri)
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(theme.surface).cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)

                    dividerLine

                    // Ảnh nền
                    segmentHeader("Ảnh nền toàn màn hình")
                    VStack(spacing: 8) {
                        Button {
                            showImagePicker = true
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "photo.badge.plus").font(.system(size: 18))
                                Text("Chọn ảnh từ thư viện iPhone")
                                    .font(.system(size: 15, weight: .medium))
                                Spacer()
                            }
                            .foregroundColor(theme.textPri)
                            .padding(.vertical, 14)
                            .background(theme.surface).cornerRadius(14)
                        }
                        .padding(.horizontal)

                        if let img = wallImage ?? theme.wallImage {
                            Image(uiImage: img)
                                .resizable().scaledToFill()
                                .frame(height: 120)
                                .clipped().cornerRadius(12)
                                .padding(.horizontal)
                        }

                        if theme.hasWall {
                            VStack(spacing: 0) {
                                wallSlider("Lớp phủ tối",  value: $theme.wallOvl, range: 0...1, scale: 100)
                                Divider().background(theme.divider)
                                wallSlider("Độ sáng",       value: $theme.wallBri, range: 0.5...2, scale: 100)
                                Divider().background(theme.divider)
                                wallSlider("Độ bão hoà",    value: $theme.wallSat, range: 0.5...2, scale: 100)
                                Divider().background(theme.divider)
                                Button(role: .destructive) {
                                    theme.removeWall(); wallImage = nil
                                } label: {
                                    Text("Xoá ảnh nền").foregroundColor(.red)
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                }
                            }
                            .background(theme.surface).cornerRadius(14)
                            .padding(.horizontal)
                        }
                    }

                    Spacer(minLength: 30)
                }
                .padding(.top, 16)
            }
        }
        .navigationTitle("Chủ đề & Màu sắc")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showImagePicker) {
            ImagePickerView(sourceType: .photoLibrary) { img in
                theme.saveWall(img)
                wallImage = img  // local preview
            }
        }
        .onAppear {
            pickerR = theme.accentR; pickerG = theme.accentG; pickerB = theme.accentB
            wallImage = theme.wallImage
        }
    }

    private func isCurrentAccent(_ rgb: (Double,Double,Double)) -> Bool {
        abs(theme.accentR - rgb.0) < 0.05 && abs(theme.accentG - rgb.1) < 0.05 && abs(theme.accentB - rgb.2) < 0.05
    }

    private func segmentHeader(_ text: String) -> some View {
        Text(text).font(.system(size: 13, weight: .semibold))
            .foregroundColor(theme.textSec).padding(.horizontal)
    }

    private var dividerLine: some View {
        Divider().background(theme.divider).padding(.horizontal)
    }

    private func colorSlider(_ label: String, value: Binding<Double>, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(label).font(.system(size: 13)).foregroundColor(theme.textPri).frame(width: 90, alignment: .leading)
            Slider(value: value, in: 0...1).tint(color)
            Text(String(format: "%.0f", value.wrappedValue * 255))
                .font(.system(size: 12)).foregroundColor(theme.textSec).frame(width: 32)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(theme.surface).cornerRadius(10)
    }

    private func wallSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, scale: Int) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(label).font(.system(size: 14)).foregroundColor(theme.textPri)
                Spacer()
                Text("\(Int(value.wrappedValue * Double(scale)))%").font(.system(size: 13)).foregroundColor(theme.textSec)
            }
            Slider(value: value, in: range).tint(theme.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }
}

// MARK: - History list (simple)

struct HistoryListView: View {
    @EnvironmentObject var theme: ThemeManager
    @StateObject private var histMgr = HistoryManager.shared

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            if histMgr.sessions.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock").font(.system(size: 40)).foregroundColor(theme.textSec)
                    Text("Chưa có lịch sử").foregroundColor(theme.textSec)
                }
            } else {
                List {
                    ForEach(histMgr.sessions) { s in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.title).font(.system(size: 14, weight: .semibold)).foregroundColor(theme.textPri)
                            Text(s.preview).font(.system(size: 12)).foregroundColor(theme.textSec).lineLimit(2)
                        }
                        .padding(.vertical, 2)
                        .listRowBackground(theme.surface)
                    }
                    .onDelete { idx in idx.forEach { histMgr.delete(session: histMgr.sessions[$0]) } }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("Lịch sử chat")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .onAppear { histMgr.loadSessions() }
    }
}

// MARK: - SettingsView (backward compat — API Keys)

struct SettingsView: View {
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
        NavigationStack {
            Form {
                Section("Giọng nói") {
                    Toggle("Tự động đọc to câu trả lời", isOn: $autoSpeakReplies)
                    Picker("Giọng đọc", selection: $voiceGenderRaw) {
                        ForEach(VoiceGender.allCases) { g in Text(g.rawValue).tag(g.rawValue) }
                    }
                }
                Section { SecureField("Azure TTS key", text: $azureKey)
                    TextField("Region (vd: southeastasia)", text: $azureRegion)
                } header: { Text("Azure TTS") }
                Section("AI Memory") { Toggle("Tự động ghi nhớ thông tin", isOn: $autoMemory) }
                providerSection("ChatGPT (OpenAI)",      key: $openAIKey,    placeholder: "sk-...",     model: $openAIModel,    mode: .openai)
                providerSection("Claude (Anthropic)",    key: $anthropicKey, placeholder: "sk-ant-...", model: $anthropicModel, mode: .anthropic)
                providerSection("Gemini (Google)",       key: $geminiKey,    placeholder: "AIza...",    model: $geminiModel,    mode: .gemini)
                providerSection("Grok (xAI)",            key: $grokKey,      placeholder: "xai-...",    model: $grokModel,      mode: .grok)
                providerSection("DeepSeek",              key: $deepseekKey,  placeholder: "sk-...",     model: $deepseekModel,  mode: .deepseek)
                providerSection("Groq (Llama – Miễn phí)", key: $groqKey,   placeholder: "gsk_...",    model: $groqModel,      mode: .groq)
                Section { Text("API key được lưu trong Keychain của máy.").font(.footnote).foregroundColor(.secondary) }
            }
            .navigationTitle("API Keys")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        KeychainHelper.save(openAIKey, forKey: AIProviderKind.openAI.keychainKey)
                        KeychainHelper.save(anthropicKey, forKey: AIProviderKind.anthropic.keychainKey)
                        KeychainHelper.save(geminiKey, forKey: AIProviderKind.gemini.keychainKey)
                        KeychainHelper.save(grokKey, forKey: AIProviderKind.grok.keychainKey)
                        KeychainHelper.save(deepseekKey, forKey: AIProviderKind.deepseek.keychainKey)
                        KeychainHelper.save(groqKey, forKey: AIProviderKind.groq.keychainKey)
                        KeychainHelper.save(azureKey, forKey: "azure_tts_key")
                        KeychainHelper.save(azureRegion, forKey: "azure_tts_region")
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
                        case .openai: return try await OpenAIModelFetcher.fetchModels(apiKey: openAIKey)
                        case .anthropic: return try await AnthropicModelFetcher.fetchModels(apiKey: anthropicKey)
                        case .gemini: return try await GeminiModelFetcher.fetchModels(apiKey: geminiKey)
                        case .grok: return try await GrokModelFetcher.fetchModels(apiKey: grokKey)
                        case .deepseek: return try await DeepSeekModelFetcher.fetchModels(apiKey: deepseekKey)
                        case .groq: return try await GroqModelFetcher.fetchModels(apiKey: groqKey)
                        }
                    }
                )
            }
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

// MARK: - ModelPickerMode + ModelPickerView (giữ nguyên)

enum ModelPickerMode: String, Identifiable {
    case openai, anthropic, gemini, grok, deepseek, groq
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openai: return "Chọn model OpenAI"; case .anthropic: return "Chọn model Anthropic"
        case .gemini: return "Chọn model Gemini";  case .grok: return "Chọn model Grok"
        case .deepseek: return "Chọn model DeepSeek"; case .groq: return "Chọn model Groq"
        }
    }
    func binding(openAI: Binding<String>, anthropic: Binding<String>, gemini: Binding<String>,
                 grok: Binding<String>, deepseek: Binding<String>, groq: Binding<String>) -> Binding<String> {
        switch self {
        case .openai: return openAI; case .anthropic: return anthropic; case .gemini: return gemini
        case .grok: return grok; case .deepseek: return deepseek; case .groq: return groq
        }
    }
}

struct ModelPickerView: View {
    let title: String
    @Binding var currentModel: String
    let fetch: () async throws -> [String]
    @Environment(\.dismiss) private var dismiss
    @State private var models: [String] = []
    @State private var isLoading = true
    @State private var errorText: String?
    var body: some View {
        NavigationStack {
            Group {
                if isLoading { ProgressView("Đang hỏi server...") }
                else if let e = errorText {
                    VStack(spacing: 12) {
                        Text(e).font(.footnote).foregroundColor(.red).padding()
                        Button("Thử lại") { Task { await load() } }
                    }
                } else if models.isEmpty { Text("Không tìm thấy model nào.")
                } else {
                    List(models, id: \.self) { m in
                        Button { currentModel = m; dismiss() } label: {
                            HStack {
                                Text(m); Spacer()
                                if m == currentModel { Image(systemName: "checkmark").foregroundColor(.blue) }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }
            .task { await load() }
        }
    }
    private func load() async {
        isLoading = true; errorText = nil
        do { models = try await fetch() } catch { errorText = error.localizedDescription }
        isLoading = false
    }
}
