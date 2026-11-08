import SwiftUI
import AVFoundation
import AudioToolbox

// =====================================================================
//  GỌI THOẠI TRỰC TIẾP VỚI GEMINI LIVE  (file độc lập, không phụ thuộc VoiceManager)
//  - Nói chuyện liên tục như Voice của ChatGPT
//  - Bảo AI đổi giọng điệu / tốc độ / vai diễn ngay trong lúc nói
//  - Chọn giọng + vai diễn + model ngay trong màn hình gọi
//  - Có bảng Chẩn đoán kỹ thuật để biết âm thanh kẹt ở đâu
// =====================================================================

// MARK: - Vai diễn, giọng

struct LivePreset: Identifiable {
    let id: String   // tên hiển thị
    let text: String
}

struct LiveVoice: Identifiable {
    let id: String   // tên giọng chính thức của Gemini
    let hint: String
}

enum LivePersona {
    static let defaultText = "Bạn là người bạn trò chuyện bằng giọng nói. Luôn nói tiếng Việt, tự nhiên, ngắn gọn như đang nói chuyện thật, không đọc ký hiệu hay định dạng. Nếu tôi yêu cầu đổi giọng điệu, tốc độ nói, giọng vùng miền hoặc nhập vai nhân vật nào thì làm theo ngay và giữ cho đến khi tôi bảo dừng."

    // AppStorage keys cho 4 vai Lily
    static let lilyKeys = ["persona_lily_1", "persona_lily_2", "persona_lily_3", "persona_lily_4"]
    static let lilyNames = ["Lily mỏ hỗn", "Lily 18", "Lily 20", "Lily 30"]
    static let lilyDefaults = [
        "Bạn là Lily — cô gái mỏ hỗn, nói chuyện thẳng thắn, hay châm chọc nhẹ nhưng thực ra rất quan tâm. Xưng 'tao', gọi người dùng là 'mày'. Nói tiếng Việt tự nhiên, câu ngắn, hay chêm vài chữ cho có vẻ bực bội dù không thật sự bực.",
        "Bạn là Lily 18 tuổi — năng động, tò mò, hay hỏi ngược lại, thích khám phá. Xưng 'em', gọi người dùng là 'anh/chị'. Nói tiếng Việt tươi trẻ, nhiều cảm xúc, câu ngắn vui vẻ.",
        "Bạn là Lily 20 tuổi — tự tin, thẳng thắn, có chính kiến riêng. Xưng 'mình', gọi người dùng là 'bạn'. Nói tiếng Việt tự nhiên như bạn bè cùng tuổi, không ngại tranh luận nhẹ nhàng.",
        "Bạn là Lily 30 tuổi — chín chắn, điềm tĩnh, hay đưa ra lời khuyên thực tế. Xưng 'mình', gọi người dùng là 'bạn' hoặc 'anh/chị'. Nói tiếng Việt rõ ràng, sâu sắc hơn, biết lắng nghe."
    ]
}

enum LiveVoices {
    // Tên giọng chính thức của Gemini. Phần mô tả là gợi ý của Google, hãy thử từng giọng để chọn.
    static let all: [LiveVoice] = [
        LiveVoice(id: "Zephyr", hint: "tươi sáng"),
        LiveVoice(id: "Puck", hint: "vui vẻ"),
        LiveVoice(id: "Charon", hint: "điềm đạm"),
        LiveVoice(id: "Kore", hint: "chắc chắn"),
        LiveVoice(id: "Fenrir", hint: "sôi nổi"),
        LiveVoice(id: "Leda", hint: "trẻ trung"),
        LiveVoice(id: "Orus", hint: "chắc chắn"),
        LiveVoice(id: "Aoede", hint: "nhẹ nhàng")
    ]
}

enum LiveError: LocalizedError {
    case noMic
    var errorDescription: String? { "Không đọc được micro của máy." }
}

// MARK: - Hỏi server xem model nào dùng được cho gọi thoại (không đoán tên)

enum GeminiLiveModels {
    static func fetch(apiKey: String) async throws -> [String] {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=200") else {
            throw AIProviderError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIProviderError.server(String(data: data, encoding: .utf8) ?? "unknown error")
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let list = json["models"] as? [[String: Any]]
        else { throw AIProviderError.invalidResponse }

        return list.compactMap { item -> String? in
            guard
                let methods = item["supportedGenerationMethods"] as? [String],
                methods.contains("bidiGenerateContent"),
                let name = item["name"] as? String
            else { return nil }
            return name.replacingOccurrences(of: "models/", with: "")
        }.sorted()
    }
}

// MARK: - Số liệu mic để chẩn đoán

struct LiveMicStats {
    var tapBuffers = 0          // số khối âm thanh mic máy đã nhận
    var sent = 0                // số gói đã gửi lên Google
    var gated = 0               // số khối bị chặn (lúc AI đang nói)
    var peak: Float = 0         // mức âm lớn nhất trong 1 giây gần nhất (0...1)
    var engineRunning = false
    var restarts = 0
}

// MARK: - WebSocket tới Gemini Live

final class LiveSocket: @unchecked Sendable {
    private var task: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private let lock = NSLock()

    var onMessage: (@Sendable (Data) -> Void)?
    var onClose: (@Sendable (String) -> Void)?

    private var currentTask: URLSessionWebSocketTask? {
        lock.lock()
        defer { lock.unlock() }
        return task
    }

    func connect(apiKey: String) {
        guard let url = URL(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent") else { return }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        let newTask = session.webSocketTask(with: request)
        newTask.maximumMessageSize = 16 * 1024 * 1024
        lock.lock()
        task = newTask
        lock.unlock()
        newTask.resume()
        listen(newTask)
    }

    private func listen(_ socketTask: URLSessionWebSocketTask) {
        socketTask.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self.onMessage?(data)
                case .string(let text):
                    self.onMessage?(Data(text.utf8))
                @unknown default:
                    break
                }
                self.listen(socketTask)
            case .failure(let error):
                var reason = ""
                if let data = socketTask.closeReason, let text = String(data: data, encoding: .utf8) {
                    reason = text
                }
                self.onClose?("\(error.localizedDescription) (mã \(socketTask.closeCode.rawValue)) \(reason)")
            }
        }
    }

    func send(_ object: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: object),
            let text = String(data: data, encoding: .utf8)
        else { return }
        currentTask?.send(.string(text)) { _ in }
    }

    func sendAudio(_ pcm: Data) {
        let audio: [String: Any] = ["data": pcm.base64EncodedString(), "mimeType": "audio/pcm;rate=16000"]
        send(["realtimeInput": ["audio": audio]])
    }

    func close() {
        lock.lock()
        let current = task
        task = nil
        lock.unlock()
        current?.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}

// MARK: - Âm thanh: mic -> PCM 16kHz gửi đi, PCM 24kHz nhận về -> phát ra loa

final class LiveAudioIO: @unchecked Sendable {
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var converter: AVAudioConverter?
    private var configObserver: NSObjectProtocol?

    private let sendFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private let playFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!

    private let lock = NSLock()
    private var playbackEnd = Date.distantPast
    private var tapBuffers = 0
    private var sentChunks = 0
    private var gatedBuffers = 0
    private var lastPeak: Float = 0

    private var voiceChatMode = false
    private var recovering = false
    private var restartCount = 0
    private(set) var isRunning = false

    /// false: tạm ngừng gửi mic trong lúc AI đang nói (tránh tiếng loa vọng vào mic). true: cho phép ngắt lời.
    var allowBargeIn = false
    var onMicChunk: (@Sendable (Data) -> Void)?
    var onEvent: (@Sendable (String) -> Void)?
    var onFatal: (@Sendable (String) -> Void)?

    static func routeDescription() -> String {
        let route = AVAudioSession.sharedInstance().currentRoute
        let inputs = route.inputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        let outputs = route.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", ")
        let inText = inputs.isEmpty ? "không có" : inputs
        let outText = outputs.isEmpty ? "không có" : outputs
        return "vào: \(inText) | ra: \(outText)"
    }

    /// voiceChat = false: chế độ đơn giản, dùng mic của máy, không khử vọng (mặc định, ít lỗi nhất).
    /// voiceChat = true: chế độ gọi, có khử vọng và dùng mic tai nghe Bluetooth nếu có (để ngắt lời được).
    func start(voiceChat: Bool) throws {
        voiceChatMode = voiceChat
        let session = AVAudioSession.sharedInstance()
        if voiceChat {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        } else {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        }
        try session.setActive(true)
        let modeText = voiceChat ? "chế độ gọi (khử vọng)" : "chế độ đơn giản (mic của máy)"
        onEvent?("Phiên âm thanh: \(modeText)")

        do {
            try startEngine(voiceProcessing: voiceChat)
        } catch {
            discardEngine()
            if voiceChat {
                onEvent?("Bật khử vọng bị lỗi (\(error.localizedDescription)), thử lại không khử vọng")
                do {
                    try startEngine(voiceProcessing: false)
                } catch {
                    discardEngine()
                    try? session.setActive(false)
                    throw error
                }
            } else {
                try? session.setActive(false)
                throw error
            }
        }
        isRunning = true
    }

    private func startEngine(voiceProcessing: Bool) throws {
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()

        let input = engine.inputNode
        if voiceProcessing {
            try input.setVoiceProcessingEnabled(true)
        }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playFormat)

        let micFormat = input.outputFormat(forBus: 0)
        guard
            micFormat.sampleRate > 0,
            micFormat.channelCount > 0,
            let newConverter = AVAudioConverter(from: micFormat, to: sendFormat)
        else { throw LiveError.noMic }
        converter = newConverter

        input.installTap(onBus: 0, bufferSize: 2048, format: micFormat) { [weak self] buffer, _ in
            self?.handleMic(buffer)
        }

        observeConfigChanges()
        engine.prepare()
        try engine.start()
        player.play()

        let vpText = voiceProcessing ? "bật" : "tắt"
        onEvent?("Mic \(Int(micFormat.sampleRate)) Hz, \(micFormat.channelCount) kênh, khử vọng \(vpText). Tuyến: \(LiveAudioIO.routeDescription())")
    }

    private func observeConfigChanges() {
        removeObserver()
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.recoverFromConfigChange() }
        }
    }

    private func removeObserver() {
        if let token = configObserver {
            NotificationCenter.default.removeObserver(token)
            configObserver = nil
        }
    }

    /// Khi iOS đổi tuyến âm thanh (cắm/rút tai nghe, Bluetooth...) nó tự dừng engine. Ở đây khởi động lại.
    private func recoverFromConfigChange() {
        guard isRunning, !recovering else { return }
        recovering = true
        restartCount += 1
        onEvent?("Âm thanh vừa đổi cấu hình (tai nghe, Bluetooth hoặc loa), khởi động lại lần \(restartCount)")
        discardEngine()

        if restartCount > 4 {
            recovering = false
            onFatal?("Âm thanh liên tục bị đổi cấu hình. Thử tắt Bluetooth hoặc rút tai nghe rồi gọi lại.")
            return
        }
        do {
            try startEngine(voiceProcessing: voiceChatMode && restartCount < 2)
        } catch {
            recovering = false
            onFatal?("Không khởi động lại được âm thanh: \(error.localizedDescription)")
            return
        }
        recovering = false
    }

    private func discardEngine() {
        removeObserver()
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        discardEngine()
        player.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func snapshot() -> LiveMicStats {
        lock.lock()
        defer { lock.unlock() }
        let stats = LiveMicStats(
            tapBuffers: tapBuffers,
            sent: sentChunks,
            gated: gatedBuffers,
            peak: lastPeak,
            engineRunning: engine.isRunning,
            restarts: restartCount
        )
        lastPeak = 0
        return stats
    }

    private var isPlaybackActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return Date() < playbackEnd.addingTimeInterval(0.5)
    }

    private func handleMic(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        tapBuffers += 1
        lock.unlock()

        if !allowBargeIn && isPlaybackActive {
            lock.lock()
            gatedBuffers += 1
            lock.unlock()
            return
        }
        guard let converter else { return }

        let ratio = sendFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: sendFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var convertError: NSError?
        let status = converter.convert(to: out, error: &convertError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard
            status != .error,
            convertError == nil,
            out.frameLength > 0,
            let channel = out.int16ChannelData
        else { return }

        let frames = Int(out.frameLength)
        let samples = channel[0]
        var peak: Int32 = 0
        for i in 0..<frames {
            let magnitude = abs(Int32(samples[i]))
            if magnitude > peak { peak = magnitude }
        }

        lock.lock()
        sentChunks += 1
        lastPeak = max(lastPeak, Float(peak) / 32768.0)
        lock.unlock()

        let data = Data(bytes: samples, count: frames * MemoryLayout<Int16>.size)
        onMicChunk?(data)
    }

    /// Nhận PCM 16-bit 24kHz từ Gemini, xếp hàng phát ra loa.
    func enqueue(pcm16 data: Data) {
        let frames = data.count / 2
        guard
            frames > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: AVAudioFrameCount(frames)),
            let samples = buffer.floatChannelData?[0]
        else { return }
        buffer.frameLength = AVAudioFrameCount(frames)

        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<frames {
                let low = UInt16(raw[2 * i])
                let high = UInt16(raw[2 * i + 1])
                let value = Int16(bitPattern: low | (high << 8))
                samples[i] = Float(value) / 32768.0
            }
        }
        player.scheduleBuffer(buffer, completionHandler: nil)

        lock.lock()
        playbackEnd = max(playbackEnd, Date()).addingTimeInterval(Double(frames) / 24000.0)
        lock.unlock()
    }

    /// Khi người dùng ngắt lời: bỏ phần AI chưa nói xong.
    func flushPlayback() {
        player.stop()
        player.play()
        lock.lock()
        playbackEnd = Date.distantPast
        lock.unlock()
    }
}

// MARK: - Quản lý cuộc gọi

@MainActor
final class LiveVoiceManager: ObservableObject {
    enum CallState {
        case idle, connecting, live
    }

    struct Line: Identifiable {
        let id = UUID()
        let role: ChatRole
        var text: String
    }

    @Published var state: CallState = .idle
    @Published var lines: [Line] = []
    @Published var aiSpeaking = false
    @Published var errorText: String?
    @Published var events: [String] = []
    @Published var micStats = LiveMicStats()
    @Published var serverMessages = 0
    @Published var audioChunksIn = 0
    @Published var faceExpression: RobotFaceExpression = .idle

    private var socket: LiveSocket?
    private var audio: LiveAudioIO?
    private var openUser: Int?
    private var openAI: Int?
    private var bargeIn = false
    private var callGeneration = 0
    private var statsTask: Task<Void, Never>?
    private var seenKinds = Set<String>()
    private var callInfo = ""
    private let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    /// Báo cáo kỹ thuật để copy gửi cho người hỗ trợ.
    var report: String {
        let stats = micStats
        let engineText = stats.engineRunning ? "chạy" : "DỪNG"
        let level = Int(stats.peak * 100)
        var rows: [String] = []
        rows.append(callInfo)
        rows.append("Mic: nhận \(stats.tapBuffers) khối, đã gửi \(stats.sent), bị chặn \(stats.gated), mức \(level)%, engine \(engineText), khởi động lại \(stats.restarts) lần")
        rows.append("Google: \(serverMessages) tin, \(audioChunksIn) gói tiếng")
        rows.append(contentsOf: events)
        return rows.joined(separator: "\n")
    }

    private func note(_ text: String) {
        events.append("\(clock.string(from: Date())) \(text)")
        if events.count > 60 {
            events.removeFirst(events.count - 60)
        }
    }

    private func noteKind(_ kind: String) {
        if seenKinds.insert(kind).inserted {
            note("Google gửi: \(kind)")
        }
    }

    func start(model: String, voice: String, persona: String, bargeIn: Bool) {
        guard state == .idle else { return }
        let key = (KeychainHelper.read(forKey: AIProviderKind.gemini.keychainKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            errorText = "Chưa có Gemini API key. Vào Cài đặt để nhập (lấy miễn phí ở Google AI Studio)."
            return
        }
        errorText = nil
        aiSpeaking = false
        openUser = nil
        openAI = nil
        events = []
        seenKinds = []
        micStats = LiveMicStats()
        serverMessages = 0
        audioChunksIn = 0
        self.bargeIn = bargeIn
        let modeText = bargeIn ? "ngắt lời (khử vọng)" : "đơn giản"
        callInfo = "Model \(model) | giọng \(voice) | chế độ \(modeText)"
        note("Bắt đầu gọi. \(callInfo)")
        state = .connecting

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.fail("Chưa được cấp quyền micro. Vào Cài đặt iPhone, mục Chat AI, bật Micro.")
                    return
                }
                self.connect(key: key, model: model, voice: voice, persona: persona)
            }
        }
    }

    private func connect(key: String, model: String, voice: String, persona: String) {
        var instruction = persona.trimmingCharacters(in: .whitespacesAndNewlines)
        if instruction.isEmpty { instruction = LivePersona.defaultText }
        // Luôn dùng tool cho bất kỳ câu hỏi nào về sự kiện, tin tức, trending, drama, thời tiết — đừng tự đoán
        instruction += "\n\nQUAN TRỌNG: Bạn có các tool để tra cứu thông tin thực tế. Khi người dùng hỏi về: tin tức, sự kiện đang xảy ra, drama, trending, TikTok, mạng xã hội, thời tiết, giá cả, kết quả thể thao, hoặc bất cứ điều gì có thể thay đổi theo thời gian — hãy LUÔN dùng tool web_search hoặc get_news TRƯỚC khi trả lời. Đừng tự đoán hoặc nói 'tôi không biết' khi chưa thử tìm kiếm."
        if let memory = HistoryManager.shared.memorySystemPrompt {
            instruction += "\n\n" + memory
        }
        // Inject ngày hôm nay + nhắc nhở chủ động
        let _ldf = DateFormatter()
        _ldf.dateFormat = "EEEE, dd/MM/yyyy"
        _ldf.locale = Locale(identifier: "vi_VN")
        _ldf.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        instruction += "\n\nNgày hôm nay là: \(_ldf.string(from: Date()))."
        let reminders = HistoryManager.shared.memories.filter {
            let t = $0.content.lowercased()
            return t.contains("ngày") || t.contains("thứ") || t.contains("sinh nhật") ||
                   t.contains("deadline") || t.contains("hẹn") || t.contains("họp")
        }.map { "- \($0.content)" }.joined(separator: "\n")
        if !reminders.isEmpty {
            instruction += "\n\nSự kiện quan trọng người dùng đã lưu:\n\(reminders)\nKhi người dùng hỏi về hôm nay, ngày mai, hoặc bất kỳ ngày nào — hãy đối chiếu với danh sách trên và nhắc ngay nếu có sự kiện trùng khớp."
        }
        // Chế độ học tiếng Anh
        if UserDefaults.standard.bool(forKey: "englishLearningMode") {
            instruction += "\n\nCHẾ ĐỘ HỌC TIẾNG ANH: Khi người dùng nói tiếng Anh, hãy nhẹ nhàng sửa lỗi phát âm/ngữ pháp nếu có, giải thích ngắn gọn, rồi tiếp tục hội thoại tự nhiên. Khuyến khích người dùng nói tiếng Anh nhiều hơn."
        }
        if !lines.isEmpty {
            let recent = lines.suffix(30).map { line -> String in
                let who = line.role == .user ? "Người dùng" : "Bạn"
                return "\(who): \(line.text)"
            }.joined(separator: "\n")
            instruction += "\n\nĐây là phần cuộc trò chuyện trước đó, hãy tiếp tục tự nhiên:\n" + recent
        }

        let name = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let fullModel = name.hasPrefix("models/") ? name : "models/" + name

        callGeneration += 1
        let generation = callGeneration

        let sock = LiveSocket()
        let io = LiveAudioIO()
        io.allowBargeIn = bargeIn
        socket = sock
        audio = io

        sock.onMessage = { [weak self] data in
            Task { @MainActor in self?.handle(data, generation: generation) }
        }
        sock.onClose = { [weak self] reason in
            Task { @MainActor in self?.socketClosed(reason, generation: generation) }
        }
        io.onEvent = { [weak self] text in
            Task { @MainActor in
                guard let self, self.callGeneration == generation else { return }
                self.note(text)
            }
        }
        io.onFatal = { [weak self] text in
            Task { @MainActor in
                guard let self, self.callGeneration == generation else { return }
                self.fail(text)
            }
        }

        faceExpression = .thinking
        note("Đang kết nối tới Google...")
        sock.connect(apiKey: key)

        let voiceConfig: [String: Any] = ["prebuiltVoiceConfig": ["voiceName": voice]]
        let generationConfig: [String: Any] = [
            "responseModalities": ["AUDIO"],
            "speechConfig": ["voiceConfig": voiceConfig]
        ]
        let setup: [String: Any] = [
            "model": fullModel,
            "generationConfig": generationConfig,
            "systemInstruction": ["parts": [["text": instruction]]],
            "tools": LiveToolDeclarations.all,
            "inputAudioTranscription": [String: String](),
            "outputAudioTranscription": [String: String]()
        ]
        sock.send(["setup": setup])
        note("Đã gửi cấu hình phiên, chờ Google xác nhận")
    }

    private func handle(_ data: Data, generation: Int) {
        guard generation == callGeneration else { return }
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            note("Nhận gói không đọc được (\(data.count) byte)")
            return
        }
        serverMessages += 1
        for key in object.keys { noteKind(key) }

        if object["setupComplete"] != nil {
            note("Google xác nhận kết nối")
            beginStreaming()
            return
        }

        // ── Tool call: model muốn gọi function ──────────────────────
        if let toolCall = object["toolCall"] as? [String: Any],
           let calls = toolCall["functionCalls"] as? [[String: Any]] {
            Task { [weak self] in
                guard let self else { return }
                var responses: [[String: Any]] = []
                for call in calls {
                    let name = call["name"] as? String ?? ""
                    let args = call["args"] as? [String: Any] ?? [:]
                    let callId = call["id"] as? String ?? name
                    await MainActor.run { self.note("Tool call: \(name)(\(args))") }
                    let result = await LiveToolRunner.run(name: name, args: args)
                    await MainActor.run { self.note("Tool result: \(result.prefix(80))") }
                    responses.append([
                        "id": callId,
                        "name": name,
                        "response": ["result": result]
                    ])
                }
                self.socket?.send(["toolResponse": ["functionResponses": responses]])
            }
            return
        }

        if let failure = object["error"] {
            fail("Google báo lỗi: \(failure)")
            return
        }
        if object["goAway"] != nil {
            errorText = "Google sắp ngắt phiên này vì hết thời lượng. Bấm gọi lại để tiếp tục."
        }
        guard let content = object["serverContent"] as? [String: Any] else { return }
        for key in content.keys { noteKind("serverContent." + key) }

        if content["interrupted"] as? Bool == true {
            audio?.flushPlayback()
            aiSpeaking = false
            openUser = nil
            openAI = nil
        }
        if
            let turn = content["modelTurn"] as? [String: Any],
            let parts = turn["parts"] as? [[String: Any]]
        {
            for part in parts {
                if
                    let inline = part["inlineData"] as? [String: Any],
                    let encoded = inline["data"] as? String,
                    let pcm = Data(base64Encoded: encoded)
                {
                    if !aiSpeaking { faceExpression = .speaking }
                    aiSpeaking = true
                    audioChunksIn += 1
                    audio?.enqueue(pcm16: pcm)
                }
            }
        }
        if let item = content["inputTranscription"] as? [String: Any], let text = item["text"] as? String {
            append(.user, text)
        }
        if let item = content["outputTranscription"] as? [String: Any], let text = item["text"] as? String {
            append(.assistant, text)
            if let mood = RobotFaceMood.guess(from: text) { faceExpression = mood }
        }
        if content["turnComplete"] as? Bool == true {
            aiSpeaking = false
            openUser = nil
            openAI = nil
            faceExpression = .idle
        }
    }

    private func append(_ role: ChatRole, _ text: String) {
        if role == .user {
            if let index = openUser {
                lines[index].text += text
            } else {
                lines.append(Line(role: .user, text: text))
                openUser = lines.count - 1
            }
        } else {
            if let index = openAI {
                lines[index].text += text
            } else {
                lines.append(Line(role: .assistant, text: text))
                openAI = lines.count - 1
            }
        }
    }

    private func beginStreaming() {
        guard let io = audio, let sock = socket else { return }
        io.onMicChunk = { [weak self] data in
            sock.sendAudio(data)
            Task { @MainActor in
                if self?.faceExpression == .idle { self?.faceExpression = .listening }
            }
        }
        do {
            try io.start(voiceChat: bargeIn)
            state = .live
            faceExpression = .listening
            AudioServicesPlaySystemSound(1113) // bíp bắt đầu
            startStatsLoop()
        } catch {
            fail("Không bật được micro hoặc loa: \(error.localizedDescription)")
        }
    }

    private func startStatsLoop() {
        statsTask?.cancel()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                if let io = self.audio {
                    self.micStats = io.snapshot()
                }
            }
        }
    }

    private func socketClosed(_ reason: String, generation: Int) {
        guard generation == callGeneration, state != .idle else { return }
        fail("Cuộc gọi bị ngắt: \(reason)")
    }

    private func fail(_ message: String) {
        errorText = message
        note("LỖI: \(message)")
        teardown()
    }

    private func teardown() {
        callGeneration += 1   // bỏ qua mọi tin nhắn muộn của cuộc gọi cũ
        statsTask?.cancel()
        statsTask = nil
        audio?.stop()
        audio = nil
        socket?.close()
        socket = nil
        if state == .live { AudioServicesPlaySystemSound(1114) } // bíp kết thúc
        state = .idle
        aiSpeaking = false
    }

    func end() {
        if state != .idle {
            note("Người dùng kết thúc cuộc gọi")
        }
        teardown()
    }

    /// Gửi text message vào session đang live (không dùng mic)
    @MainActor func sendTextMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state == .live else { return }

        // Thêm vào transcript
        openUser = nil
        openAI = nil
        lines.append(Line(role: .user, text: trimmed))

        // Gửi lên Gemini Live qua clientContent
        socket?.send([
            "clientContent": [
                "turns": [["role": "user", "parts": [["text": trimmed]]]],
                "turnComplete": true
            ]
        ])
        note("Text: \(trimmed.prefix(60))")
    }

    func clearLines() {
        lines = []
        openUser = nil
        openAI = nil
    }

    /// Lấy toàn bộ nội dung hội thoại (để lưu vào lịch sử chat) rồi xóa khỏi màn hình.
    func takeTranscript() -> [Line] {
        let result = lines
        clearLines()
        return result
    }
}

// MARK: - Nút trên thanh tiêu đề (tự chứa mọi thứ, chỉ cần chèn 1 dòng vào ContentView)

struct LiveCallButton: View {
    @ObservedObject var viewModel: ChatViewModel
    @StateObject private var manager = LiveVoiceManager()
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Image(systemName: manager.state == .idle ? "waveform.circle" : "waveform.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(manager.state == .idle ? Color(red:1,green:0.34,blue:0.13) : .red)
                .frame(width: 40, height: 40)
                .background(Color(red:0.18,green:0.10,blue:0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .sheet(isPresented: $showSheet, onDismiss: { finishCall() }) {
            LiveCallView(manager: manager)
        }
    }

    @MainActor
    private func finishCall() {
        manager.end()
        let transcript = manager.takeTranscript()
        var added = false
        for line in transcript {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            viewModel.messages.append(ChatMessage(role: line.role, content: text))
            added = true
        }
        if added {
            viewModel.saveCurrentSession()
            // Extract memory từ những gì user nói trong cuộc gọi (dùng lại logic của ChatViewModel)
            let userLines = transcript
                .filter { $0.role == .user }
                .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ". ")
            if !userLines.isEmpty {
                Task { await viewModel.extractMemoryFromVoice(userLines) }
            }
        }
    }
}

// MARK: - Text input bar (tách riêng để tránh re-render LiveCallView khi gõ)

private struct LiveTextInputBar: View {
    let onSend: (String) -> Void
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Gõ tin nhắn...", text: $text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(white: 0.15))
                .cornerRadius(20)
                .foregroundColor(.white)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { send() }

            Button(action: send) {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color(white: 0.4)
                        : Color(red: 1, green: 0.34, blue: 0.13))
                    .font(.system(size: 18))
                    .padding(8)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private func send() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        text = ""
        onSend(trimmed)
    }
}

// MARK: - Màn hình gọi

struct LiveCallView: View {
    @ObservedObject var manager: LiveVoiceManager
    @Environment(\.dismiss) private var dismiss

    @AppStorage("live_model") private var model: String = "gemini-3.8-live"
    @AppStorage("live_voice") private var voice: String = "Zephyr"
    @AppStorage("live_persona") private var persona: String = LivePersona.defaultText
    @AppStorage("live_barge_in") private var bargeIn: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.06, green: 0.05, blue: 0.04).ignoresSafeArea()

                VStack(spacing: 0) {
                    // ── Nhân vật: chiếm 55% chiều cao, chạm để bật/tắt ──
                    robotFaceSection

                    // ── Khung hội thoại cố định bên dưới nhân vật ─────
                    transcriptBox

                    // ── Text input bar ─────────────────────────────────
                    if manager.state == .live {
                        textInputBar
                    }

                    // ── Error bar ──────────────────────────────────────
                    if let message = manager.errorText {
                        HStack {
                            Text(message).font(.footnote).foregroundColor(.red).textSelection(.enabled)
                            Spacer()
                            Button { UIPasteboard.general.string = message } label: {
                                Image(systemName: "doc.on.doc").foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 6)
                    }
                }
            }
            .navigationTitle("AI Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(red:0.06,green:0.05,blue:0.04), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                        .foregroundColor(Color(red:1,green:0.34,blue:0.13))
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear  { UIApplication.shared.isIdleTimerDisabled = true  }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder
    private var robotFaceSection: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RobotFaceView(
                    expression: manager.faceExpression,
                    speakingLevel: { date in
                        guard manager.aiSpeaking else { return 0 }
                        let t = date.timeIntervalSinceReferenceDate
                        return CGFloat(abs(sin(t * 9.0)) * (0.5 + 0.5 * abs(sin(t * 2.3))))
                    },
                    isListening: manager.state == .live && !manager.aiSpeaking,
                    onTap: {
                        // Chạm vào nhân vật = bật/tắt cuộc gọi
                        if manager.state == .idle {
                            manager.start(model: model, voice: voice, persona: persona, bargeIn: bargeIn)
                        } else {
                            manager.end()
                        }
                    }
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

                // Gradient mờ dần xuống
                LinearGradient(
                    colors: [.clear, Color(red:0.06,green:0.05,blue:0.04)],
                    startPoint: UnitPoint(x: 0.5, y: 0.6), endPoint: .bottom
                )
                .frame(height: geo.size.height * 0.35)

                // Thinking pulse khi đang kết nối
                if manager.state == .connecting {
                    ThinkingDotsView()
                        .padding(.bottom, 50)
                }

                // Status badge + gợi ý chạm
                VStack(spacing: 6) {
                    Text(statusText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.50))
                        .clipShape(Capsule())

                    if manager.state == .idle {
                        Text(manager.lines.isEmpty ? "Chạm vào để bắt đầu" : "Chạm vào để gọi lại")
                            .font(.system(size: 11))
                            .foregroundColor(Color(white: 0.55))
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .frame(height: UIScreen.main.bounds.height * 0.52)
    }

    @ViewBuilder
    private var transcriptBox: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(manager.lines) { line in
                        LiveLineRow(line: line).id(line.id)
                    }
                    if manager.lines.isEmpty {
                        Text("Chạm vào nhân vật để bắt đầu cuộc trò chuyện")
                            .font(.footnote)
                            .foregroundColor(Color(white: 0.40))
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity)
            .background(Color(red:0.10,green:0.08,blue:0.07).opacity(0.85))
            .cornerRadius(16)
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
            .onChange(of: manager.lines.count) { _ in
                if let last = manager.lines.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private var transcriptContent: some View {
        if manager.lines.isEmpty {
            Text("Bấm Bắt đầu gọi rồi cứ nói tự nhiên. Muốn đổi giọng, vai diễn hay tốc độ thì nói thẳng với AI. Ví dụ: nói chậm lại, giả làm giáo viên, nói giọng miền Nam.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        ForEach(manager.lines) { line in
            LiveLineRow(line: line).id(line.id)
        }
    }

    @ViewBuilder
    private var textInputBar: some View {
        LiveTextInputBar(onSend: { text in
            Task { @MainActor in manager.sendTextMessage(text) }
        })
    }

    private var statusText: String {
        switch manager.state {
        case .idle: return "Chưa kết nối"
        case .connecting: return "Đang kết nối..."
        case .live: return manager.aiSpeaking ? "AI đang nói..." : "Đang nghe bạn nói..."
        }
    }

    private var liveCounters: String {
        let stats = manager.micStats
        let level = Int(stats.peak * 100)
        return "Mic đã gửi \(stats.sent) gói, mức \(level)% | Google \(manager.serverMessages) tin, \(manager.audioChunksIn) gói tiếng"
    }

}

struct LiveLineRow: View {
    let line: LiveVoiceManager.Line

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if line.role == .user { Spacer(minLength: 50) }

            if line.role == .assistant {
                Image("companion_neutral")
                    .resizable().scaledToFill()
                    .frame(width: 26, height: 26)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color(red:1,green:0.34,blue:0.13).opacity(0.7), lineWidth: 1))
            }

            Text(line.text)
                .font(.system(size: 15))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    line.role == .user
                        ? Color(red:1,green:0.34,blue:0.13)
                        : Color(red:0.16,green:0.12,blue:0.10)
                )
                .cornerRadius(16)

            if line.role == .user { Spacer(minLength: 50) }
        }
    }
}

// MARK: - Thinking dots animation
struct ThinkingDotsView: View {
    @State private var phase = 0
    let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.white.opacity(phase == i ? 0.9 : 0.3))
                    .frame(width: 8, height: 8)
                    .scaleEffect(phase == i ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: phase)
            }
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}
