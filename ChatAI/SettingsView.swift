import SwiftUI

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
                        ForEach(VoiceGender.allCases) { g in
                            Text(g.rawValue).tag(g.rawValue)
                        }
                    }
                }

                Section {
                    SecureField("Azure TTS key (F0 miễn phí)", text: $azureKey)
                    TextField("Region (vd: southeastasia)", text: $azureRegion)
                } header: {
                    Text("Azure TTS – giọng neural tiếng Việt")
                } footer: {
                    Text("Đăng ký miễn phí tại portal.azure.com → Speech. Nếu để trống dùng giọng iOS mặc định.")
                        .font(.caption)
                }

                Section("AI Memory") {
                    Toggle("Tự động ghi nhớ thông tin", isOn: $autoMemory)
                }

                providerSection(
                    title: "ChatGPT (OpenAI)",
                    key: $openAIKey,
                    placeholder: "sk-...",
                    model: $openAIModel,
                    mode: .openai
                )
                providerSection(
                    title: "Claude (Anthropic)",
                    key: $anthropicKey,
                    placeholder: "sk-ant-...",
                    model: $anthropicModel,
                    mode: .anthropic
                )
                providerSection(
                    title: "Gemini (Google)",
                    key: $geminiKey,
                    placeholder: "AIza...",
                    model: $geminiModel,
                    mode: .gemini
                )
                providerSection(
                    title: "Grok (xAI)",
                    key: $grokKey,
                    placeholder: "xai-...",
                    model: $grokModel,
                    mode: .grok
                )
                providerSection(
                    title: "DeepSeek",
                    key: $deepseekKey,
                    placeholder: "sk-...",
                    model: $deepseekModel,
                    mode: .deepseek
                )
                providerSection(
                    title: "Groq (Llama – Miễn phí)",
                    key: $groqKey,
                    placeholder: "gsk_...",
                    model: $groqModel,
                    mode: .groq
                )

                Section {
                    Text("API key được lưu trong Keychain của máy, không gửi đi đâu khác ngoài provider tương ứng.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Cài đặt")
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
                    currentModel: mode.binding(
                        openAI:    $openAIModel,
                        anthropic: $anthropicModel,
                        gemini:    $geminiModel,
                        grok:      $grokModel,
                        deepseek:  $deepseekModel,
                        groq:      $groqModel
                    ),
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
    private func providerSection(
        title: String,
        key: Binding<String>,
        placeholder: String,
        model: Binding<String>,
        mode: ModelPickerMode
    ) -> some View {
        Section(title) {
            SecureField(placeholder, text: key)
            HStack {
                Text(model.wrappedValue)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Chọn model") {
                    pickerMode = mode
                }
                .font(.footnote)
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

    func binding(
        openAI: Binding<String>,
        anthropic: Binding<String>,
        gemini: Binding<String>,
        grok: Binding<String>,
        deepseek: Binding<String>,
        groq: Binding<String>
    ) -> Binding<String> {
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
                        Text(errorText)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .padding()
                        Button("Thử lại") { Task { await load() } }
                    }
                } else if models.isEmpty {
                    Text("Không tìm thấy model nào.")
                } else {
                    List(models, id: \.self) { model in
                        Button {
                            currentModel = model
                            dismiss()
                        } label: {
                            HStack {
                                Text(model)
                                Spacer()
                                if model == currentModel {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
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
        isLoading = true
        errorText = nil
        do { models = try await fetch() }
        catch { errorText = error.localizedDescription }
        isLoading = false
    }
}
