import SwiftUI
import PhotosUI

// MARK: - Theme colors (dùng chung toàn app)
// Được lưu vào AppStorage để áp dụng toàn app

struct AppColors {
    static let accent    = Color(red:1.00, green:0.34, blue:0.13)
    static let bg        = Color(red:0.08, green:0.06, blue:0.05)
    static let surface   = Color(red:0.14, green:0.11, blue:0.09)
    static let textPri   = Color.white
    static let textSec   = Color(white:0.60)
    static let divider   = Color(white:0.18)
}

// MARK: - Settings root (tab Cài đặt)

struct SettingsTabRootView: View {
    @State private var showSettings     = false
    @State private var showRobotPreview = false
    @StateObject private var histMgr    = HistoryManager.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.bg.ignoresSafeArea()
                List {
                    // ── Profile header ────────────────────────────────
                    Section {
                        HStack(spacing: 14) {
                            if let img = UIImage(named: "companion_neutral") {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(AppColors.accent, lineWidth: 2))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("ChatAI")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(AppColors.textPri)
                                Text("TP Signature")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppColors.accent)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(AppColors.surface)

                    // ── Tuỳ chỉnh AI ─────────────────────────────────
                    Section {
                        NavigationLink {
                            VoiceSettingsView()
                        } label: {
                            settingsRow(icon: "waveform", label: "Giọng nói", value: "")
                        }

                        NavigationLink {
                            ModelAISettingsView()
                        } label: {
                            settingsRow(icon: "cpu", label: "Model AI", value: "")
                        }

                        Button {
                            showRobotPreview = true
                        } label: {
                            settingsRow(icon: "face.smiling", label: "AI Companion", value: "Xem biểu cảm")
                        }
                    } header: {
                        sectionHeader(icon: "slider.horizontal.3", text: "TUỲ CHỈNH AI")
                    }
                    .listRowBackground(AppColors.surface)

                    // ── Giao diện ─────────────────────────────────────
                    Section {
                        NavigationLink {
                            ThemeSettingsView()
                        } label: {
                            settingsRow(icon: "paintpalette", label: "Chủ đề & Màu sắc", value: "")
                        }
                    } header: {
                        sectionHeader(icon: "paintbrush", text: "GIAO DIỆN")
                    }
                    .listRowBackground(AppColors.surface)

                    // ── AI Memory ─────────────────────────────────────
                    Section {
                        NavigationLink {
                            MemorySettingsView()
                        } label: {
                            settingsRow(icon: "brain", label: "AI Memory",
                                        value: "\(histMgr.memories.count)/50")
                        }
                    } header: {
                        sectionHeader(icon: "brain.head.profile", text: "AI MEMORY")
                    }
                    .listRowBackground(AppColors.surface)

                    // ── API Keys ──────────────────────────────────────
                    Section {
                        Button {
                            showSettings = true
                        } label: {
                            settingsRow(icon: "key.horizontal", label: "API Keys", value: "")
                        }
                    } header: {
                        sectionHeader(icon: "lock.shield", text: "KẾT NỐI")
                    }
                    .listRowBackground(AppColors.surface)

                    // ── Footer ────────────────────────────────────────
                    Section {
                        HStack {
                            settingsRow(icon: "info.circle", label: "Phiên bản", value: "")
                            Spacer()
                            Text("1.0")
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.textSec)
                        }
                    }
                    .listRowBackground(AppColors.surface)
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Cài đặt")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(AppColors.bg, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showRobotPreview) { RobotFacePreviewView() }
    }

    private func settingsRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(AppColors.accent)
                .frame(width: 28)
            Text(label)
                .font(.system(size: 15))
                .foregroundColor(AppColors.textPri)
            if !value.isEmpty {
                Spacer()
                Text(value)
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSec)
            }
        }
    }

    private func sectionHeader(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(AppColors.accent)
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(AppColors.accent)
        }
    }
}

// MARK: - Giọng nói

struct VoiceSettingsView: View {
    @AppStorage("autoSpeakReplies") var autoSpeakReplies: Bool = false
    @AppStorage("voiceGender")      var voiceGenderRaw: String = VoiceGender.female.rawValue
    @State private var azureKey:    String = KeychainHelper.read(forKey: "azure_tts_key") ?? ""
    @State private var azureRegion: String = KeychainHelper.read(forKey: "azure_tts_region") ?? ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()
            Form {
                Section {
                    Toggle("Tự động đọc to câu trả lời", isOn: $autoSpeakReplies)
                        .tint(AppColors.accent)
                    Picker("Giọng đọc", selection: $voiceGenderRaw) {
                        ForEach(VoiceGender.allCases) { g in
                            Text(g.rawValue).tag(g.rawValue)
                        }
                    }
                } header: {
                    Text("GIỌNG NÓI")
                        .foregroundColor(AppColors.accent)
                }
                .listRowBackground(AppColors.surface)

                Section {
                    SecureField("Azure TTS key", text: $azureKey)
                        .foregroundColor(AppColors.textPri)
                    TextField("Region (vd: southeastasia)", text: $azureRegion)
                        .foregroundColor(AppColors.textPri)
                } header: {
                    Text("AZURE TTS – GIỌNG NEURAL TIẾNG VIỆT")
                        .foregroundColor(AppColors.accent)
                } footer: {
                    Text("Đăng ký miễn phí tại portal.azure.com → Speech. Nếu để trống dùng giọng iOS mặc định.")
                        .foregroundColor(AppColors.textSec)
                }
                .listRowBackground(AppColors.surface)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Giọng nói")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Lưu") {
                    KeychainHelper.save(azureKey,    forKey: "azure_tts_key")
                    KeychainHelper.save(azureRegion, forKey: "azure_tts_region")
                    dismiss()
                }
                .foregroundColor(AppColors.accent)
            }
        }
    }
}

// MARK: - Model AI

struct ModelAISettingsView: View {
    @AppStorage("selected_provider") var selectedProviderRaw: String = AIProviderKind.gemini.rawValue
    @AppStorage("model_openai")    var openAIModel:    String = AIProviderKind.openAI.defaultModel
    @AppStorage("model_anthropic") var anthropicModel: String = AIProviderKind.anthropic.defaultModel
    @AppStorage("model_gemini")    var geminiModel:    String = AIProviderKind.gemini.defaultModel
    @AppStorage("model_grok")      var grokModel:      String = AIProviderKind.grok.defaultModel
    @AppStorage("model_deepseek")  var deepseekModel:  String = AIProviderKind.deepseek.defaultModel
    @AppStorage("model_groq")      var groqModel:      String = AIProviderKind.groq.defaultModel

    @State private var openAIKey:    String = KeychainHelper.read(forKey: AIProviderKind.openAI.keychainKey) ?? ""
    @State private var anthropicKey: String = KeychainHelper.read(forKey: AIProviderKind.anthropic.keychainKey) ?? ""
    @State private var geminiKey:    String = KeychainHelper.read(forKey: AIProviderKind.gemini.keychainKey) ?? ""
    @State private var grokKey:      String = KeychainHelper.read(forKey: AIProviderKind.grok.keychainKey) ?? ""
    @State private var deepseekKey:  String = KeychainHelper.read(forKey: AIProviderKind.deepseek.keychainKey) ?? ""
    @State private var groqKey:      String = KeychainHelper.read(forKey: AIProviderKind.groq.keychainKey) ?? ""
    @State private var pickerMode:   ModelPickerMode?

    private let providers: [(AIProviderKind, String, String, String)] = [
        (.openAI,    "ChatGPT",  "Trò chuyện · Đa năng · Sáng tạo",    "openai_logo"),
        (.anthropic, "Claude",   "An toàn · Logic · Phân tích",          "anthropic_logo"),
        (.gemini,    "Gemini",   "Đa phương thức · Kết nối Google",      "gemini_logo"),
        (.grok,      "Grok",     "Nhanh · Thời sự · Sáng tạo",           "grok_logo"),
        (.deepseek,  "DeepSeek", "Lý luận · Code · Phân tích",           "deepseek_logo"),
        (.groq,      "Groq",     "Miễn phí · Nhanh · Linh hoạt",         "groq_logo"),
    ]

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()
            Form {
                Section {
                    ForEach(providers, id: \.0) { (kind, name, desc, _) in
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                selectedProviderRaw = kind.rawValue
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "cpu")
                                        .font(.system(size: 18))
                                        .foregroundColor(selectedProviderRaw == kind.rawValue ? AppColors.accent : AppColors.textSec)
                                        .frame(width: 32)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(AppColors.textPri)
                                        Text(desc)
                                            .font(.system(size: 12))
                                            .foregroundColor(AppColors.textSec)
                                    }
                                    Spacer()
                                    if selectedProviderRaw == kind.rawValue {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(AppColors.accent)
                                    } else {
                                        Circle()
                                            .stroke(AppColors.textSec, lineWidth: 1.5)
                                            .frame(width: 22, height: 22)
                                    }
                                }
                                .padding(.vertical, 6)
                            }

                            // API key field khi đang chọn provider này
                            if selectedProviderRaw == kind.rawValue {
                                Divider().background(AppColors.divider)
                                HStack {
                                    SecureField(kind.keychainKey.contains("openai") ? "sk-..." :
                                                kind.keychainKey.contains("anthropic") ? "sk-ant-..." :
                                                kind.keychainKey.contains("gemini") ? "AIza..." :
                                                kind.keychainKey.contains("grok") ? "xai-..." : "key...",
                                                text: keyBinding(for: kind))
                                        .foregroundColor(AppColors.textPri)
                                        .font(.system(size: 13))
                                    Spacer()
                                    Button("Tải model") {
                                        pickerMode = pickerModeFor(kind)
                                    }
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(AppColors.accent)
                                }
                                .padding(.top, 6)
                                Text(modelFor(kind))
                                    .font(.system(size: 12))
                                    .foregroundColor(AppColors.textSec)
                                    .lineLimit(1)
                                    .padding(.top, 2)
                            }
                        }
                    }
                } header: {
                    Text("MÔ HÌNH AI")
                        .foregroundColor(AppColors.accent)
                }
                .listRowBackground(AppColors.surface)
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Model AI")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Lưu") { saveKeys() }
                    .foregroundColor(AppColors.accent)
            }
        }
        .sheet(item: $pickerMode) { mode in
            ModelPickerView(
                title: mode.title,
                currentModel: mode.binding(
                    openAI: $openAIModel, anthropic: $anthropicModel,
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

    private func keyBinding(for kind: AIProviderKind) -> Binding<String> {
        switch kind {
        case .openAI:    return $openAIKey
        case .anthropic: return $anthropicKey
        case .gemini:    return $geminiKey
        case .grok:      return $grokKey
        case .deepseek:  return $deepseekKey
        case .groq:      return $groqKey
        }
    }
    private func modelFor(_ kind: AIProviderKind) -> String {
        switch kind {
        case .openAI:    return openAIModel
        case .anthropic: return anthropicModel
        case .gemini:    return geminiModel
        case .grok:      return grokModel
        case .deepseek:  return deepseekModel
        case .groq:      return groqModel
        }
    }
    private func pickerModeFor(_ kind: AIProviderKind) -> ModelPickerMode {
        switch kind {
        case .openAI:    return .openai
        case .anthropic: return .anthropic
        case .gemini:    return .gemini
        case .grok:      return .grok
        case .deepseek:  return .deepseek
        case .groq:      return .groq
        }
    }
    private func saveKeys() {
        KeychainHelper.save(openAIKey,    forKey: AIProviderKind.openAI.keychainKey)
        KeychainHelper.save(anthropicKey, forKey: AIProviderKind.anthropic.keychainKey)
        KeychainHelper.save(geminiKey,    forKey: AIProviderKind.gemini.keychainKey)
        KeychainHelper.save(grokKey,      forKey: AIProviderKind.grok.keychainKey)
        KeychainHelper.save(deepseekKey,  forKey: AIProviderKind.deepseek.keychainKey)
        KeychainHelper.save(groqKey,      forKey: AIProviderKind.groq.keychainKey)
    }
}

// MARK: - Chủ đề & Màu sắc

struct ThemePreset: Identifiable {
    let id: String
    let name: String
    let desc: String
    let gradientColors: [Color]
    let accentHex: String
}

let themePresets: [ThemePreset] = [
    ThemePreset(id:"fire",    name:"Hỏa cao cấp",  desc:"Đỏ cam · Than chì · Ánh kim",
                gradientColors:[Color(red:0.7,green:0.15,blue:0.05),Color(red:0.10,green:0.07,blue:0.06)], accentHex:"FF5721"),
    ThemePreset(id:"dawn",    name:"Bình minh",     desc:"Cam ấm · Hoàng hôn",
                gradientColors:[Color(red:0.8,green:0.40,blue:0.10),Color(red:0.12,green:0.09,blue:0.07)], accentHex:"FF9A3C"),
    ThemePreset(id:"nature",  name:"Thiên nhiên",   desc:"Xanh trầm · Than chì",
                gradientColors:[Color(red:0.05,green:0.35,blue:0.15),Color(red:0.06,green:0.09,blue:0.07)], accentHex:"2ECC71"),
    ThemePreset(id:"minimal", name:"Tối giản",      desc:"Trung tính · Tinh gọn",
                gradientColors:[Color(red:0.25,green:0.25,blue:0.28),Color(red:0.08,green:0.08,blue:0.09)], accentHex:"AAAAAA"),
]

let accentColors: [Color] = [
    Color(red:1.00,green:0.34,blue:0.13), Color(red:1.00,green:0.60,blue:0.10),
    Color(red:0.95,green:0.85,blue:0.40), Color(red:0.55,green:0.25,blue:0.95),
    Color(red:0.18,green:0.80,blue:0.44), Color(red:0.40,green:0.40,blue:0.45),
    Color(red:0.75,green:0.75,blue:0.78), Color(red:0.12,green:0.12,blue:0.14),
    Color(red:0.90,green:0.20,blue:0.30), Color(red:1.00,green:0.50,blue:0.15),
    Color(red:0.95,green:0.77,blue:0.20), Color(red:0.90,green:0.88,blue:0.55),
    Color(red:0.40,green:0.85,blue:0.95), Color(red:0.25,green:0.55,blue:0.90),
    Color(red:0.15,green:0.30,blue:0.75), Color(red:0.55,green:0.25,blue:0.70),
    Color(red:0.75,green:0.30,blue:0.60), Color(red:0.88,green:0.35,blue:0.45),
    Color(red:0.20,green:0.55,blue:0.25), Color(red:0.40,green:0.60,blue:0.20),
    Color(red:0.55,green:0.70,blue:0.10), Color(red:0.10,green:0.70,blue:0.55),
    Color(red:0.05,green:0.65,blue:0.65), Color(red:0.95,green:0.95,blue:0.95),
]

struct ThemeSettingsView: View {
    @AppStorage("theme_preset")       var themePreset:    String = "fire"
    @AppStorage("theme_opacity")      var themeOpacity:   Double = 0.60
    @AppStorage("wallpaper_overlay")  var wallOverlay:    Double = 0.47
    @AppStorage("wallpaper_bright")   var wallBright:     Double = 1.12
    @AppStorage("wallpaper_sat")      var wallSat:        Double = 1.09
    @AppStorage("has_wallpaper")      var hasWallpaper:   Bool = false

    @State private var showImagePicker = false
    @State private var selectedImage:   UIImage?

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // ── 4 chủ đề ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Chủ đề giao diện")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.textSec)
                            .padding(.horizontal)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(themePresets) { preset in
                                Button {
                                    themePreset = preset.id
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        ZStack(alignment: .topTrailing) {
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(LinearGradient(
                                                    colors: preset.gradientColors,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing))
                                                .frame(height: 80)
                                                .overlay(
                                                    VStack(alignment: .leading, spacing: 5) {
                                                        Spacer()
                                                        RoundedRectangle(cornerRadius: 3)
                                                            .fill(.white.opacity(0.6))
                                                            .frame(width: 50, height: 5)
                                                        RoundedRectangle(cornerRadius: 3)
                                                            .fill(.white.opacity(0.35))
                                                            .frame(width: 35, height: 4)
                                                        Spacer().frame(height: 8)
                                                    }
                                                    .padding(.horizontal, 10)
                                                )
                                            if themePreset == preset.id {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(AppColors.accent)
                                                    .background(Color.white.clipShape(Circle()))
                                                    .padding(6)
                                            }
                                        }
                                        Text(preset.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(AppColors.textPri)
                                        Text(preset.desc)
                                            .font(.system(size: 11))
                                            .foregroundColor(AppColors.textSec)
                                    }
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14)
                                        .stroke(themePreset == preset.id ? AppColors.accent : Color.clear, lineWidth: 2)
                                )
                            }
                        }
                        .padding(.horizontal)
                    }

                    Divider().background(AppColors.divider).padding(.horizontal)

                    // ── Màu sắc accent ────────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Màu sắc")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.textSec)
                            .padding(.horizontal)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                            ForEach(Array(accentColors.enumerated()), id: \.offset) { _, color in
                                Circle()
                                    .fill(color)
                                    .frame(width: 42, height: 42)
                                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                            }
                        }
                        .padding(.horizontal)
                    }

                    Divider().background(AppColors.divider).padding(.horizontal)

                    // ── Độ trong suốt ─────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Độ trong suốt")
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.textPri)
                            Spacer()
                            Text("\(Int(themeOpacity * 100))%")
                                .font(.system(size: 13))
                                .foregroundColor(AppColors.textSec)
                        }
                        Slider(value: $themeOpacity, in: 0...1)
                            .tint(AppColors.accent)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(AppColors.surface)
                    .cornerRadius(14)
                    .padding(.horizontal)

                    // ── Ảnh nền ───────────────────────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ảnh nền toàn màn hình")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppColors.textSec)
                            .padding(.horizontal)

                        Button {
                            showImagePicker = true
                        } label: {
                            HStack {
                                Spacer()
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 18))
                                Text("Chọn ảnh từ thư viện")
                                    .font(.system(size: 15, weight: .medium))
                                Spacer()
                            }
                            .foregroundColor(AppColors.textPri)
                            .padding(.vertical, 14)
                            .background(AppColors.surface)
                            .cornerRadius(14)
                        }
                        .padding(.horizontal)

                        if hasWallpaper {
                            VStack(spacing: 0) {
                                sliderRow(label: "Lớp phủ tối",  value: $wallOverlay, range: 0...1,  suffix: "%", scale: 100)
                                Divider().background(AppColors.divider)
                                sliderRow(label: "Độ sáng",      value: $wallBright,  range: 0.5...2, suffix: "%", scale: 100)
                                Divider().background(AppColors.divider)
                                sliderRow(label: "Độ bão hoà",   value: $wallSat,     range: 0.5...2, suffix: "%", scale: 100)
                                Divider().background(AppColors.divider)
                                Button(role: .destructive) {
                                    hasWallpaper = false
                                } label: {
                                    Text("Xoá ảnh nền")
                                        .foregroundColor(.red)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                }
                            }
                            .background(AppColors.surface)
                            .cornerRadius(14)
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
                selectedImage = img
                hasWallpaper = true
            }
        }
    }

    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String, scale: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textPri)
                Spacer()
                Text("\(Int(value.wrappedValue * Double(scale)))\(suffix)")
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSec)
            }
            Slider(value: value, in: range)
                .tint(AppColors.accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Memory settings

struct MemorySettingsView: View {
    @StateObject private var histMgr = HistoryManager.shared
    @AppStorage("autoMemory") var autoMemory: Bool = true

    var body: some View {
        ZStack {
            AppColors.bg.ignoresSafeArea()
            Form {
                Section {
                    Toggle("Tự động ghi nhớ thông tin", isOn: $autoMemory)
                        .tint(AppColors.accent)
                        .foregroundColor(AppColors.textPri)
                } header: {
                    Text("AI MEMORY")
                        .foregroundColor(AppColors.accent)
                }
                .listRowBackground(AppColors.surface)

                Section {
                    ForEach(histMgr.memories) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.content)
                                .font(.system(size: 14))
                                .foregroundColor(AppColors.textPri)
                            Text(item.savedAt, style: .date)
                                .font(.system(size: 11))
                                .foregroundColor(AppColors.textSec)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { idx in
                        idx.forEach { histMgr.deleteMemory(histMgr.memories[$0]) }
                    }
                } header: {
                    Text("GHI NHỚ (\(histMgr.memories.count)/50)")
                        .foregroundColor(AppColors.accent)
                }
                .listRowBackground(AppColors.surface)

                if !histMgr.memories.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            histMgr.clearAllMemory()
                        } label: {
                            Text("Xóa tất cả bộ nhớ")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .listRowBackground(AppColors.surface)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("AI Memory")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
    }
}

// MARK: - SettingsView (API Keys - giữ nguyên từ bản cũ)

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
                Section("AI Memory") {
                    Toggle("Tự động ghi nhớ thông tin", isOn: $autoMemory)
                }
                providerSection("ChatGPT (OpenAI)",     key: $openAIKey,    placeholder: "sk-...",     model: $openAIModel,    mode: .openai)
                providerSection("Claude (Anthropic)",   key: $anthropicKey, placeholder: "sk-ant-...", model: $anthropicModel, mode: .anthropic)
                providerSection("Gemini (Google)",      key: $geminiKey,    placeholder: "AIza...",    model: $geminiModel,    mode: .gemini)
                providerSection("Grok (xAI)",           key: $grokKey,      placeholder: "xai-...",    model: $grokModel,      mode: .grok)
                providerSection("DeepSeek",             key: $deepseekKey,  placeholder: "sk-...",     model: $deepseekModel,  mode: .deepseek)
                providerSection("Groq (Llama – Miễn phí)", key: $groqKey,  placeholder: "gsk_...",    model: $groqModel,      mode: .groq)
                Section {
                    Text("API key được lưu trong Keychain của máy và chỉ dùng với provider tương ứng.")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle("API Keys")
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

// MARK: - ModelPickerMode

enum ModelPickerMode: String, Identifiable {
    case openai, anthropic, gemini, grok, deepseek, groq
    var id: String { rawValue }
    var title: String {
        switch self {
        case .openai:    return "Chọn model OpenAI"
        case .anthropic: return "Chọn model Anthropic"
        case .gemini:    return "Chọn model Gemini"
        case .grok:      return "Chọn model Grok"
        case .deepseek:  return "Chọn model DeepSeek"
        case .groq:      return "Chọn model Groq"
        }
    }
    func binding(openAI: Binding<String>, anthropic: Binding<String>, gemini: Binding<String>,
                 grok: Binding<String>, deepseek: Binding<String>, groq: Binding<String>) -> Binding<String> {
        switch self {
        case .openai:    return openAI
        case .anthropic: return anthropic
        case .gemini:    return gemini
        case .grok:      return grok
        case .deepseek:  return deepseek
        case .groq:      return groq
        }
    }
}

// MARK: - ModelPickerView

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
                if isLoading {
                    ProgressView("Đang hỏi server...")
                } else if let errorText {
                    VStack(spacing: 12) {
                        Text(errorText).font(.footnote).foregroundColor(.red).padding()
                        Button("Thử lại") { Task { await load() } }
                    }
                } else if models.isEmpty {
                    Text("Không tìm thấy model nào.")
                } else {
                    List(models, id: \.self) { model in
                        Button {
                            currentModel = model; dismiss()
                        } label: {
                            HStack {
                                Text(model)
                                Spacer()
                                if model == currentModel {
                                    Image(systemName: "checkmark").foregroundColor(AppColors.accent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true; errorText = nil
        do { models = try await fetch() }
        catch { errorText = error.localizedDescription }
        isLoading = false
    }
}

// SettingsTabView = alias cho ContentView.swift gọi đúng tên
typealias SettingsTabView = SettingsTabRootView
