# Project Checkpoint — Tpios Chat AI

**Repo:** `https://github.com/tpios-facebooktp88/Tpios-chat-ai` (public, branch `main`)  
**Stack:** Swift/iOS 16+, XcodeGen (`project.yml`), build qua Codemagic → IPA  
**Folder code:** `ChatAI/` — XcodeGen quét toàn bộ, thêm file `.swift` vào đây là tự build

---

## Kiến trúc chính

| File | Vai trò |
|------|---------|
| `LiveVoice.swift` | WebSocket tới Gemini Live — mic → PCM 16kHz gửi đi, PCM 24kHz nhận về phát loa |
| `LiveTools.swift` | Function calling: 4 tools (weather/news/search/datetime), không cần API key thêm |
| `CompanionView.swift` | Nhân vật 3D — 8 biểu cảm, lip-sync theo âm thanh AI |
| `Services.swift` | Text chat: Gemini, OpenAI, Anthropic, Groq |
| `ChatViewModel.swift` | State quản lý hội thoại |
| `HistoryManager.swift` | Lưu lịch sử chat |
| `SettingsView.swift` | Cài đặt API key, model, giọng, nhân vật |
| `ContentView.swift` | Root UI |
| `ThemeManager.swift` | Dark/light theme |
| `AttachmentService.swift` | Đính kèm ảnh/file vào chat |

---

## Gemini Live — Function Calling

AI có thể gọi tool trong lúc nói chuyện giọng nói. Luồng:

```
User nói → Gemini Live xử lý
  → gửi toolCall { name, args } qua WebSocket
  → LiveVoice.handle() bắt, dispatch tới LiveToolRunner
  → LiveToolRunner fetch API (async)
  → gửi toolResponse { result } về Google
  → model đọc kết quả → nói ra loa
```

### 4 tools hiện có (LiveTools.swift)

| Tool | API | Key cần |
|------|-----|---------|
| `get_weather` | wttr.in | Không |
| `get_news` | Google News RSS | Không |
| `web_search` | DuckDuckGo Instant Answer | Không |
| `get_datetime` | local | Không |

### Thêm tool mới

Chỉ cần sửa `LiveTools.swift` — 2 chỗ:

```swift
// 1. Thêm khai báo vào LiveToolDeclarations.all
FunctionDeclaration(name: "ten_tool", description: "...", parameters: ...)

// 2. Thêm case vào LiveToolRunner.run()
case "ten_tool": return await myFunction(args)
```

Không cần đụng `LiveVoice.swift`.

---

## Ảnh nhân vật

8 file `ChatAI/companion_*.webp` — WebP quality=85, tổng 785KB (gốc PNG 7.6MB).

- SwiftUI `Image("companion_neutral")` → load tự động, không cần extension
- `UIImage(named:)` → cần explicit: `UIImage(named: "companion_neutral.webp")`

---

## Build

```yaml
# codemagic.yaml đã có sẵn — trigger tự động khi push main
# XcodeGen chạy từ project.yml trước khi build
```

Không cần config thêm sau khi thêm file `.swift` hay `.webp` vào `ChatAI/`.

---

## Việc có thể làm tiếp

- Thêm tool mới vào Gemini Live (xem hướng dẫn ở trên)
- Nâng chất lượng tool: thêm API key OpenWeatherMap / NewsAPI vào Settings nếu muốn kết quả chính xác hơn
- Thêm provider giọng nói khác (ElevenLabs, OpenAI TTS) vào `VoiceManager.swift`
- Thêm biểu cảm nhân vật mới: thêm ảnh `.webp` vào `ChatAI/`, map vào `RobotFaceExpression`
