import Foundation
import AVFoundation
import SwiftUI

// MARK: - Groq Whisper STT

struct GroqWhisper {
    /// Upload file âm thanh lên Groq Whisper, nhận về text tiếng Việt
    static func transcribe(fileURL: URL, apiKey: String) async throws -> String {
        guard !apiKey.isEmpty else { throw AIProviderError.missingAPIKey }

        let url = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let audioData = try Data(contentsOf: fileURL)

        // File field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-large-v3-turbo\r\n".data(using: .utf8)!)

        // Language field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("vi\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AIProviderError.server(String(data: data, encoding: .utf8) ?? "Whisper error")
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = json["text"] as? String
        else { throw AIProviderError.invalidResponse }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Azure TTS

struct AzureTTS {
    static func speak(text: String, apiKey: String, region: String, gender: VoiceGender) async -> Data? {
        guard !apiKey.isEmpty, !region.isEmpty else { return nil }
        let voiceName = (gender == .female) ? "vi-VN-HoaiMyNeural" : "vi-VN-NamMinhNeural"
        let ssml = "<speak version='1.0' xml:lang='vi-VN'><voice name='\(voiceName)'>\(text)</voice></speak>"
        guard let url = URL(string: "https://\(region).tts.speech.microsoft.com/cognitiveservices/v1") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        request.setValue("application/ssml+xml", forHTTPHeaderField: "Content-Type")
        request.setValue("audio-24khz-48kbitrate-mono-mp3", forHTTPHeaderField: "X-Microsoft-OutputFormat")
        request.httpBody = ssml.data(using: .utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}

// MARK: - VoiceManager

@MainActor
final class VoiceManager: NSObject, ObservableObject {
    @Published var isListening: Bool = false
    @Published var isSpeaking: Bool = false
    @Published var voiceErrorMessage: String?

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private let synthesizer = AVSpeechSynthesizer()
    private var azurePlayer: AVAudioPlayer?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Ghi âm + Whisper STT

    func startListening(
        groqAPIKey: String,
        onPartialResult: @escaping (String) -> Void,
        onFinish: @escaping (String) -> Void
    ) {
        guard !isListening else {
            stopListeningAndTranscribe(groqAPIKey: groqAPIKey, onFinish: onFinish)
            return
        }

        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            guard let self else { return }
            Task { @MainActor in
                guard granted else {
                    self.voiceErrorMessage = "Chưa được cấp quyền micro. Vào Cài đặt → Chat AI → bật Micro."
                    return
                }
                self.beginRecording(
                    groqAPIKey: groqAPIKey,
                    onPartialResult: onPartialResult,
                    onFinish: onFinish
                )
            }
        }
    }

    private func beginRecording(
        groqAPIKey: String,
        onPartialResult: @escaping (String) -> Void,
        onFinish: @escaping (String) -> Void
    ) {
        voiceErrorMessage = nil

                do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            voiceErrorMessage = "Lỗi audio session: \(error.localizedDescription)"
            return
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("voice_\(UUID().uuidString).m4a")
        recordingURL = fileURL

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.record()
            isListening = true
            onPartialResult("🎙 Đang nghe... Bấm mic lần nữa để dừng")
        } catch {
            voiceErrorMessage = "Không khởi động được ghi âm: \(error.localizedDescription)"
        }
    }

    func stopListeningAndTranscribe(groqAPIKey: String, onFinish: @escaping (String) -> Void) {
        guard isListening, let url = recordingURL else { return }

        audioRecorder?.stop()
        audioRecorder = nil
        isListening = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        guard !groqAPIKey.isEmpty else {
            voiceErrorMessage = "Cần nhập Groq API key trong Cài đặt để dùng tính năng giọng nói."
            return
        }

        Task {
            do {
                let text = try await GroqWhisper.transcribe(fileURL: url, apiKey: groqAPIKey)
                try? FileManager.default.removeItem(at: url)
                if text.isEmpty {
                    voiceErrorMessage = "Không nhận diện được giọng nói. Thử lại."
                } else {
                    onFinish(text)
                }
            } catch {
                voiceErrorMessage = "Lỗi nhận diện: \(error.localizedDescription)"
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func stopListening() {
        audioRecorder?.stop()
        audioRecorder = nil
        isListening = false
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - TTS

    func speak(text: String, gender: VoiceGender, azureKey: String, azureRegion: String) {
        guard !text.isEmpty else { return }
        Task {
            if !azureKey.isEmpty, !azureRegion.isEmpty {
                if let data = await AzureTTS.speak(text: text, apiKey: azureKey, region: azureRegion, gender: gender) {
                    do {
                        let session = AVAudioSession.sharedInstance()
                        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
                        try session.setActive(true)
                        azurePlayer = try AVAudioPlayer(data: data)
                        azurePlayer?.play()
                        isSpeaking = true
                        while azurePlayer?.isPlaying == true {
                            try? await Task.sleep(nanoseconds: 100_000_000)
                        }
                        isSpeaking = false
                        return
                    } catch {}
                }
            }
            speakFallback(text: text, gender: gender)
        }
    }

    private func speakFallback(text: String, gender: VoiceGender) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
        } catch { return }
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "vi-VN" }
        let target: AVSpeechSynthesisVoiceGender = gender == .male ? .male : .female
        let voice = voices.first { $0.gender == target } ?? voices.first ?? AVSpeechSynthesisVoice(language: "vi-VN")
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stopSpeaking() {
        azurePlayer?.stop()
        azurePlayer = nil
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

extension VoiceManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
