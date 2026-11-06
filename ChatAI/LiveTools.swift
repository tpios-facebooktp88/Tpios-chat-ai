import Foundation

// =====================================================================
//  LIVE TOOLS — Function calling cho Gemini Live
//  Thêm vào setup: tools declarations
//  handle() nhận toolCall → dispatch → gửi toolResponse
// =====================================================================

// MARK: - Khai báo tools gửi kèm setup

enum LiveToolDeclarations {
    static var all: [[String: Any]] {
        [[
            "functionDeclarations": [
                weatherDecl,
                newsDecl,
                searchDecl,
                datetimeDecl
            ]
        ]]
    }

    private static var weatherDecl: [String: Any] {[
        "name": "get_weather",
        "description": "Lấy thông tin thời tiết hiện tại tại một địa điểm.",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "location": [
                    "type": "STRING",
                    "description": "Tên thành phố hoặc địa điểm. Ví dụ: 'Ho Chi Minh City', 'Hanoi', 'Da Nang'."
                ]
            ],
            "required": ["location"]
        ]
    ]}

    private static var newsDecl: [String: Any] {[
        "name": "get_news",
        "description": "Lấy tin tức mới nhất theo chủ đề.",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "topic": [
                    "type": "STRING",
                    "description": "Chủ đề cần tìm tin. Ví dụ: 'AI', 'thể thao', 'chứng khoán', 'bóng đá'."
                ]
            ],
            "required": ["topic"]
        ]
    ]}

    private static var searchDecl: [String: Any] {[
        "name": "web_search",
        "description": "Tìm kiếm thông tin trên internet về bất kỳ chủ đề nào khi người dùng hỏi về sự kiện, kiến thức thực tế.",
        "parameters": [
            "type": "OBJECT",
            "properties": [
                "query": [
                    "type": "STRING",
                    "description": "Câu hỏi hoặc từ khóa cần tìm kiếm."
                ]
            ],
            "required": ["query"]
        ]
    ]}

    private static var datetimeDecl: [String: Any] {[
        "name": "get_datetime",
        "description": "Lấy ngày giờ hiện tại theo giờ Việt Nam.",
        "parameters": [
            "type": "OBJECT",
            "properties": [:] as [String: Any]
        ]
    ]}
}

// MARK: - Thực thi tool

enum LiveToolRunner {
    static func run(name: String, args: [String: Any]) async -> String {
        switch name {
        case "get_weather":  return await getWeather(args)
        case "get_news":     return await getNews(args)
        case "web_search":   return await webSearch(args)
        case "get_datetime": return getDatetime()
        default:             return "Tool '\(name)' không được hỗ trợ."
        }
    }

    // ── Thời tiết — OpenWeatherMap free tier (60 req/phút) ──────────
    private static func getWeather(_ args: [String: Any]) async -> String {
        guard let location = args["location"] as? String, !location.isEmpty else {
            return "Chưa có tên địa điểm."
        }
        // Dùng wttr.in — không cần API key, trả về JSON tiếng Anh
        let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? location
        let urlStr = "https://wttr.in/\(encoded)?format=j1"
        guard let url = URL(string: urlStr) else { return "Không tạo được URL thời tiết." }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let current = (json["current_condition"] as? [[String: Any]])?.first
            else { return "Không đọc được dữ liệu thời tiết từ wttr.in." }

            let temp = (current["temp_C"] as? String) ?? "?"
            let feelsLike = (current["FeelsLikeC"] as? String) ?? "?"
            let humidity = (current["humidity"] as? String) ?? "?"
            let desc = ((current["weatherDesc"] as? [[String: Any]])?.first?["value"] as? String) ?? "?"
            let wind = (current["windspeedKmph"] as? String) ?? "?"
            return "Thời tiết tại \(location): \(temp)°C (cảm giác \(feelsLike)°C), \(desc.lowercased()), độ ẩm \(humidity)%, gió \(wind) km/h."
        } catch {
            return "Lỗi khi lấy thời tiết: \(error.localizedDescription)"
        }
    }

    // ── Tin tức — NewsData.io free tier (không cần key khi dùng RSS) ─
    private static func getNews(_ args: [String: Any]) async -> String {
        guard let topic = args["topic"] as? String, !topic.isEmpty else {
            return "Chưa có chủ đề tin tức."
        }
        // RSS của Google News — không cần key
        let encoded = topic.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? topic
        let urlStr = "https://news.google.com/rss/search?q=\(encoded)&hl=vi&gl=VN&ceid=VN:vi"
        guard let url = URL(string: urlStr) else { return "Không tạo được URL tin tức." }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let xml = String(data: data, encoding: .utf8) ?? ""
            // Lấy tối đa 4 tiêu đề từ <title> (bỏ qua cái đầu tiên là tên feed)
            let titles = extractRssTitles(from: xml, max: 4)
            if titles.isEmpty { return "Không tìm được tin về '\(topic)'." }
            let numbered = titles.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
            return "Tin tức về \(topic):\n\(numbered)"
        } catch {
            return "Lỗi khi lấy tin tức: \(error.localizedDescription)"
        }
    }

    private static func extractRssTitles(from xml: String, max: Int) -> [String] {
        var results: [String] = []
        var search = xml
        var skipped = false   // bỏ qua <title> đầu tiên (tên feed)
        while results.count < max, let start = search.range(of: "<title>") {
            search = String(search[start.upperBound...])
            guard let end = search.range(of: "</title>") else { break }
            let raw = String(search[..<end.lowerBound])
                .replacingOccurrences(of: "<![CDATA[", with: "")
                .replacingOccurrences(of: "]]>", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            search = String(search[end.upperBound...])
            if !skipped { skipped = true; continue }
            if !raw.isEmpty { results.append(raw) }
        }
        return results
    }

    // ── Tìm kiếm — Google News RSS (tốt cho nội dung Việt, trending, drama) ──
    private static func webSearch(_ args: [String: Any]) async -> String {
        guard let query = args["query"] as? String, !query.isEmpty else {
            return "Chưa có từ khóa tìm kiếm."
        }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        // Thử Google News RSS trước (bắt được trending VN tốt hơn DuckDuckGo)
        let urlStr = "https://news.google.com/rss/search?q=\(encoded)&hl=vi&gl=VN&ceid=VN:vi"
        guard let url = URL(string: urlStr) else { return "Không tạo được URL tìm kiếm." }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let xml = String(data: data, encoding: .utf8) ?? ""
            let titles = extractRssTitles(from: xml, max: 5)
            if !titles.isEmpty {
                return "Kết quả tìm kiếm '\(query)':\n" + titles.enumerated().map { "\($0.offset+1). \($0.element)" }.joined(separator: "\n")
            }
            return "Không tìm được kết quả cho '\(query)'."
        } catch {
            return "Lỗi khi tìm kiếm: \(error.localizedDescription)"
        }
    }

    // ── Ngày giờ — không cần network ─────────────────────────────────
    private static func getDatetime() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")
        formatter.dateFormat = "EEEE, dd/MM/yyyy, HH:mm"
        let now = formatter.string(from: Date())
        return "Hôm nay là \(now) (giờ Việt Nam)."
    }
}
