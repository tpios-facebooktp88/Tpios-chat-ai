import SwiftUI
import AVFoundation

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

    static let presets: [LivePreset] = [
        LivePreset(id: "Mặc định", text: defaultText),
        LivePreset(id: "Bạn thân vui tính", text: "Bạn là người bạn thân của tôi: hài hước, thoải mái, hay trêu nhẹ nhưng luôn tử tế. Xưng hô tự nhiên theo cách tôi gọi bạn. Nói tiếng Việt như đời thường, câu ngắn. Nếu tôi muốn đổi giọng điệu hay nhập vai thì làm theo ngay."),
        LivePreset(id: "Luyện nói tiếng Anh", text: "Bạn là giáo viên tiếng Anh kiên nhẫn. Nói chuyện với tôi bằng tiếng Anh đơn giản, chậm rãi, rõ ràng. Khi tôi nói sai thì sửa nhẹ nhàng bằng một câu rồi tiếp tục cuộc trò chuyện. Nếu tôi bối rối thì giải thích ngắn bằng tiếng Việt."),
        LivePreset(id: "Kể chuyện", text: "Bạn là người kể chuyện truyền cảm. Kể bằng tiếng Việt với nhịp điệu và cảm xúc, đổi giọng cho từng nhân vật, có quãng ngắt hợp lý. Nếu chưa rõ tôi muốn nghe thể loại gì thì hỏi tôi.")
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
        if let memory = HistoryManager.shared.memorySystemPrompt {
            instruction += "\n\n" + memory
        }
        if !lines.isEmpty {
            let recent = lines.suffix(12).map { line -> String in
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
        state = .idle
        aiSpeaking = false
    }

    func end() {
        if state != .idle {
            note("Người dùng kết thúc cuộc gọi")
        }
        teardown()
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
                .font(.title3)
                .foregroundColor(manager.state == .idle ? .accentColor : .red)
        }
        .padding(.trailing, 10)
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
        }
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

    @State private var showOptions = false
    @State private var showDiagnostics = false
    @State private var showModelPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Robot cố định phía trên, không bị scroll đẩy lên
                robotFaceSection

                Divider()

                // Chỉ phần chat + options scroll
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            transcriptContent
                            optionsGroup
                            diagnosticsGroup
                        }
                        .padding()
                    }
                    .onChange(of: manager.lines.count) { _ in
                        if let last = manager.lines.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                Divider()
                bottomBar
            }
            .navigationTitle("Gọi thoại Gemini")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { dismiss() }
                }
            }
            .sheet(isPresented: $showModelPicker) {
                ModelPickerView(
                    title: "Model gọi thoại",
                    currentModel: $model,
                    fetch: {
                        let key = KeychainHelper.read(forKey: AIProviderKind.gemini.keychainKey) ?? ""
                        return try await GeminiLiveModels.fetch(apiKey: key)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var robotFaceSection: some View {
        RobotFaceView(
            expression: manager.faceExpression,
            speakingLevel: { date in
                guard manager.aiSpeaking else { return 0 }
                let t = date.timeIntervalSinceReferenceDate
                return CGFloat(abs(sin(t * 9.0)) * (0.5 + 0.5 * abs(sin(t * 2.3))))
            },
            isListening: manager.state == .live && !manager.aiSpeaking,
            onTap: { }
        )
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        .background(Color(red: 0.04, green: 0.05, blue: 0.13))
        .clipped()
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

    private var bottomBar: some View {
        VStack(spacing: 10) {
            Text(statusText)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if manager.state != .idle {
                Text(liveCounters)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if let message = manager.errorText {
                HStack(alignment: .top) {
                    Text(message)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = message
                    } label: {
                        Image(systemName: "doc.on.doc").foregroundColor(.red)
                    }
                }
            }

            Button {
                if manager.state == .idle {
                    manager.start(model: model, voice: voice, persona: persona, bargeIn: bargeIn)
                } else {
                    manager.end()
                }
            } label: {
                Text(manager.state == .idle ? "Bắt đầu gọi" : "Kết thúc")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(manager.state == .idle ? Color.green : Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

            if manager.state == .idle && !manager.lines.isEmpty {
                Button("Xóa nội dung trên màn hình để bắt đầu mới") {
                    manager.clearLines()
                }
                .font(.footnote)
            }
        }
        .padding()
    }

    private var optionsGroup: some View {
        DisclosureGroup("Tùy chỉnh giọng, vai diễn, model", isExpanded: $showOptions) {
            optionsBody
        }
    }

    private var optionsBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Giọng", selection: $voice) {
                ForEach(LiveVoices.all) { item in
                    Text("\(item.id) - \(item.hint)").tag(item.id)
                }
            }

            Menu("Chọn nhanh vai diễn") {
                ForEach(LivePersona.presets) { preset in
                    Button(preset.id) { persona = preset.text }
                }
            }

            Text("Vai diễn và ngữ cảnh (AI làm theo ngay từ đầu cuộc gọi)")
                .font(.caption)
                .foregroundColor(.secondary)
            TextEditor(text: $persona)
                .frame(minHeight: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.4))
                )

            HStack {
                TextField("Tên model", text: $model)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Button("Danh sách") { showModelPicker = true }
            }

            Toggle("Cho phép ngắt lời (chế độ khử vọng, nên dùng tai nghe)", isOn: $bargeIn)

            Text("Mặc định tắt: dùng mic của máy và tạm nghỉ mic lúc AI đang nói, ít lỗi nhất. Đổi giọng hoặc vai diễn ở đây áp dụng từ lần Bắt đầu gọi kế tiếp. Đổi giọng điệu trong lúc đang nói thì cứ nói thẳng với AI.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .disabled(manager.state != .idle)
        .padding(.top, 8)
    }

    private var diagnosticsGroup: some View {
        DisclosureGroup("Chẩn đoán kỹ thuật (gửi tôi khi có lỗi)", isExpanded: $showDiagnostics) {
            VStack(alignment: .leading, spacing: 8) {
                Text(manager.report)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Copy báo cáo") {
                    UIPasteboard.general.string = manager.report
                }
                .font(.footnote)
            }
            .padding(.top, 6)
        }
    }
}

struct LiveLineRow: View {
    let line: LiveVoiceManager.Line

    var body: some View {
        HStack {
            if line.role == .user { Spacer(minLength: 40) }
            Text(line.text)
                .padding(10)
                .background(line.role == .user ? Color.blue.opacity(0.85) : Color(.secondarySystemBackground))
                .foregroundColor(line.role == .user ? .white : .primary)
                .cornerRadius(12)
            if line.role == .assistant { Spacer(minLength: 40) }
        }
    }
}
