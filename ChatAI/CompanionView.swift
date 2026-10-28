import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
//  CompanionView.swift
//  AI Companion – dùng 8 ảnh thật thay cho robot vẽ bằng code
//
//  DROP-IN REPLACEMENT cho FaceView.swift:
//  • Giữ nguyên tên type RobotFaceExpression, RobotFaceMood
//  • RobotFaceView → hiện ảnh nhân vật thật với transition + lip-sync
//  • RobotFacePreviewView → gallery xem thử biểu cảm
//
//  Ảnh cần có trong ChatAI/ (cùng thư mục file .swift):
//    companion_neutral.jpg   companion_happy.jpg    companion_surprised.jpg
//    companion_thinking.jpg  companion_angry.jpg    companion_wink.jpg
//    companion_speaking.jpg  companion_sleepy.jpg
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Expression (giữ tên cũ để LiveVoice.swift không đổi gì)

enum RobotFaceExpression: String, CaseIterable, Identifiable {
    case idle, listening, thinking, speaking
    case happy, surprised, confused, sad, angry, sleepy, wink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle:      return "Bình thường"
        case .listening: return "Đang nghe"
        case .thinking:  return "Suy nghĩ"
        case .speaking:  return "Đang nói"
        case .happy:     return "Vui vẻ"
        case .surprised: return "Ngạc nhiên"
        case .confused:  return "Bối rối"
        case .sad:       return "Buồn"
        case .angry:     return "Tức giận"
        case .sleepy:    return "Buồn ngủ"
        case .wink:      return "Nháy mắt"
        }
    }

    /// Tên file ảnh tương ứng (trong bundle, thư mục ChatAI/)
    var imageName: String {
        switch self {
        case .idle, .listening, .confused, .sad:
            return "companion_neutral"
        case .happy:
            return "companion_happy"
        case .surprised:
            return "companion_surprised"
        case .thinking:
            return "companion_thinking"
        case .angry:
            return "companion_angry"
        case .wink:
            return "companion_wink"
        case .speaking:
            return "companion_speaking"
        case .sleepy:
            return "companion_sleepy"
        }
    }
}

// MARK: - Mood detector (giữ tên cũ)

enum RobotFaceMood {
    static func guess(from text: String) -> RobotFaceExpression? {
        let lower = text.lowercased()
        func has(_ phrases: [String]) -> Bool { phrases.contains { lower.contains($0) } }
        if has(["buồn ngủ", "ngáp", "mệt"])                           { return .sleepy }
        if has(["haha", "hihi", "hehe", "ha ha", "hì hì"])           { return .happy }
        if has(["thật sao", "trời ơi", "bất ngờ", "wow", "ôi"])      { return .surprised }
        if has(["hmm", "ừm", "để mình nghĩ", "để xem", "suy nghĩ"])  { return .thinking }
        if has(["xin lỗi", "rất tiếc", "tiếc quá", "buồn"])          { return .sad }
        if has(["bối rối", "không hiểu", "hả"])                       { return .confused }
        if has(["tức", "bực", "tệ", "sai rồi", "không được"])        { return .angry }
        if has(["tuyệt", "vui", "thích", "chúc mừng", "cảm ơn"])     { return .happy }
        if has(["nháy", "winky", "😉"])                                { return .wink }
        return nil
    }
}

// MARK: - Companion image view (core)

struct CompanionImageView: View {
    let expression: RobotFaceExpression
    /// 0…1, dùng để đổi sang ảnh miệng mở khi đang nói
    var speakingLevel: CGFloat = 0
    var isListening: Bool = false
    var onTap: (() -> Void)? = nil

    // Ảnh đang hiện và ảnh đang chờ transition
    @State private var currentImage: String = ""
    @State private var nextImage: String = ""
    @State private var showNext: Bool = false
    @State private var speakingFlip: Bool = false  // luân phiên speaking/neutral

    // Timer lip-sync
    @State private var lipTimer: Timer? = nil

    var body: some View {
        ZStack {
            // Layer dưới
            companionImage(currentImage)
                .opacity(showNext ? 0 : 1)

            // Layer trên (transition vào)
            companionImage(nextImage)
                .opacity(showNext ? 1 : 0)

            // Vòng sáng listening
            if isListening {
                listeningRing
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .onAppear {
            currentImage = expression.imageName
            nextImage = expression.imageName
        }
        .onChange(of: expression) { newExpr in
            crossfade(to: newExpr.imageName)
        }
        .onChange(of: speakingLevel) { level in
            handleLipSync(level: level)
        }
        .onDisappear { lipTimer?.invalidate() }
    }

    @ViewBuilder
    private func companionImage(_ name: String) -> some View {
        if let uiImage = UIImage(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .clipped()
        } else {
            // fallback nếu tên ảnh không đúng
            Color(red: 0.04, green: 0.08, blue: 0.18)
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.3))
                        Text(name)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                    }
                )
        }
    }

    private var listeningRing: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1/30)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let pulse = CGFloat((sin(t * 3.0) + 1) / 2)
                let w = geo.size.width, h = geo.size.height
                let r = min(w, h) * 0.48 + min(w, h) * 0.04 * pulse
                Circle()
                    .stroke(Color(red:0.24, green:0.90, blue:1.00).opacity(0.55 - 0.35*Double(pulse)),
                            lineWidth: 2)
                    .frame(width: r*2, height: r*2)
                    .position(x: w/2, y: h/2)
            }
        }
    }

    // MARK: Crossfade transition
    private func crossfade(to name: String) {
        guard name != currentImage else { return }
        nextImage = name
        withAnimation(.easeInOut(duration: 0.28)) {
            showNext = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            currentImage = name
            showNext = false
        }
    }

    // MARK: Lip-sync: luân phiên companion_speaking ↔ companion_neutral theo mức âm
    private func handleLipSync(level: CGFloat) {
        if level > 0.15 && expression == .speaking {
            if lipTimer == nil {
                lipTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { _ in
                    speakingFlip.toggle()
                    crossfade(to: speakingFlip ? "companion_speaking" : "companion_neutral")
                }
            }
        } else {
            lipTimer?.invalidate()
            lipTimer = nil
        }
    }
}

// MARK: - Public view (drop-in cho LiveVoice.swift)

struct RobotFaceView: View {
    var expression: RobotFaceExpression
    var speakingLevel: (Date) -> CGFloat = { _ in 0 }
    var isListening: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        TimelineView(.animation(minimumInterval: 1/15)) { tl in
            let level = speakingLevel(tl.date)
            CompanionImageView(
                expression: expression,
                speakingLevel: level,
                isListening: isListening,
                onTap: onTap
            )
        }
    }
}

// MARK: - Preview / Gallery

struct RobotFacePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expression: RobotFaceExpression = .idle
    @State private var simulateSpeech = false
    @State private var showListening  = false
    @State private var autoPlay = false
    @State private var autoTask: Task<Void, Never>?
    @State private var pokeTask:  Task<Void, Never>?

    private static func fakeSpeech(_ d: Date) -> CGFloat {
        let t = d.timeIntervalSinceReferenceDate
        return CGFloat(abs(sin(t * 9.0)) * (0.5 + 0.5 * abs(sin(t * 2.3))))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Ảnh chính
                    RobotFaceView(
                        expression: expression,
                        speakingLevel: { simulateSpeech ? RobotFacePreviewView.fakeSpeech($0) : 0 },
                        isListening: showListening,
                        onTap: { poke() }
                    )
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 6)

                    // Grid biểu cảm
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(RobotFaceExpression.allCases) { item in
                            Button {
                                autoTask?.cancel(); autoPlay = false
                                expression = item
                            } label: {
                                VStack(spacing: 6) {
                                    // Thumbnail nhỏ
                                    if let img = UIImage(named: item.imageName) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 60, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 10))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(expression == item ? Color.accentColor : Color.clear, lineWidth: 2)
                                            )
                                    }
                                    Text(item.title)
                                        .font(.caption2)
                                        .foregroundColor(expression == item ? .accentColor : .primary)
                                }
                                .padding(6)
                                .background(expression == item ? Color.accentColor.opacity(0.12) : Color.clear)
                                .cornerRadius(12)
                            }
                        }
                    }

                    Toggle("Giả lập đang nói (lip-sync)", isOn: $simulateSpeech)
                    Toggle("Vòng sáng đang nghe",          isOn: $showListening)

                    Button(autoPlay ? "Dừng chạy thử" : "Chạy thử lần lượt biểu cảm") {
                        toggleAutoPlay()
                    }
                    .font(.footnote)

                    Text("Chạm vào ảnh để trêu thử.\nBiểu cảm ở đây cũng áp dụng cho màn hình gọi thoại.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .navigationTitle("AI Companion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") {
                        autoTask?.cancel()
                        pokeTask?.cancel()
                        dismiss()
                    }
                }
            }
            .onDisappear {
                autoTask?.cancel()
                pokeTask?.cancel()
            }
        }
    }

    private func toggleAutoPlay() {
        if autoPlay { autoTask?.cancel(); autoPlay = false; return }
        autoPlay = true
        autoTask = Task {
            for item in RobotFaceExpression.allCases.filter({ $0 != .listening }) {
                guard !Task.isCancelled else { return }
                expression = item
                try? await Task.sleep(nanoseconds: 1_800_000_000)
            }
            autoPlay = false
        }
    }

    private func poke() {
        pokeTask?.cancel()
        let before = expression
        pokeTask = Task {
            expression = .surprised
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            expression = .wink
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            expression = before
        }
    }
}
