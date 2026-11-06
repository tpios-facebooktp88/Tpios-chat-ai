import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
//  SmartHomeSettings.swift
//  Lưu Home Assistant URL + token → inject vào LiveTools để điều khiển thiết bị
// ─────────────────────────────────────────────────────────────────────────────

private let kHAUrl   = "smarthome_ha_url"
private let kHAToken = "smarthome_ha_token"

// MARK: - Settings storage

enum SmartHomeConfig {
    static var url:   String { UserDefaults.standard.string(forKey: kHAUrl)   ?? "" }
    static var token: String { KeychainHelper.read(forKey: kHAToken)          ?? "" }
    static var isConfigured: Bool { !url.isEmpty && !token.isEmpty }

    static func save(url: String, token: String) {
        UserDefaults.standard.set(url, forKey: kHAUrl)
        KeychainHelper.save(token, forKey: kHAToken)
    }
}

// MARK: - Settings UI

struct SmartHomeSettingsView: View {
    @EnvironmentObject var theme: ThemeManager
    @State private var haUrl   = SmartHomeConfig.url
    @State private var haToken = SmartHomeConfig.token
    @State private var testResult: String?
    @State private var testing = false

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 32))
                            .foregroundColor(theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Home Assistant").font(.headline).foregroundColor(theme.textPri)
                            Text("Điều khiển đèn, AC, ổ cắm, TV... bằng giọng nói")
                                .font(.caption).foregroundColor(theme.textSec)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(theme.surface)

                Section("KẾT NỐI") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("URL Home Assistant").font(.caption).foregroundColor(theme.textSec)
                        TextField("http://192.168.1.x:8123", text: $haUrl)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                            .foregroundColor(theme.textPri)
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Long-Lived Access Token").font(.caption).foregroundColor(theme.textSec)
                        SecureField("eyJ0eXAi...", text: $haToken)
                            .foregroundColor(theme.textPri)
                    }
                    .padding(.vertical, 2)

                    Button {
                        SmartHomeConfig.save(url: haUrl, token: haToken)
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            if testing {
                                ProgressView().scaleEffect(0.8).tint(theme.accent)
                            } else {
                                Image(systemName: "checkmark.circle")
                            }
                            Text(testing ? "Đang kiểm tra..." : "Lưu & Kiểm tra kết nối")
                        }
                        .foregroundColor(theme.accent)
                    }
                    .disabled(haUrl.isEmpty || haToken.isEmpty || testing)

                    if let result = testResult {
                        Text(result)
                            .font(.caption)
                            .foregroundColor(result.hasPrefix("✓") ? .green : .red)
                    }
                }
                .listRowBackground(theme.surface)

                Section("HƯỚNG DẪN") {
                    VStack(alignment: .leading, spacing: 8) {
                        guideStep("1", "Cài Home Assistant trên Raspberry Pi, NAS hoặc máy tính cũ")
                        guideStep("2", "Vào Settings → Users → Create User → tạo Long-Lived Token")
                        guideStep("3", "Nhập URL (IP local hoặc domain nếu có) và token vào ô trên")
                        guideStep("4", "Nói: \"tắt đèn phòng khách\", \"bật điều hòa\", \"kiểm tra nhiệt độ\"")
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(theme.surface)

                Section("VÍ DỤ LỆNH GIỌNG NÓI") {
                    ForEach(["Tắt đèn phòng ngủ",
                             "Bật điều hòa 25 độ",
                             "Nhiệt độ trong nhà bây giờ là bao nhiêu?",
                             "Tắt tất cả đèn",
                             "Mở khóa cửa chính"], id: \.self) { cmd in
                        HStack {
                            Image(systemName: "mic.fill")
                                .font(.caption).foregroundColor(theme.accent)
                            Text(cmd).font(.subheadline).foregroundColor(theme.textPri)
                        }
                    }
                }
                .listRowBackground(theme.surface)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Smart Home")
        .toolbarBackground(theme.bg, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private func testConnection() async {
        testing = true; testResult = nil
        let result = await SmartHomeAPI.testConnection()
        await MainActor.run {
            testResult = result
            testing = false
        }
    }

    private func guideStep(_ n: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(n)
                .font(.caption.bold())
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(ThemeManager.shared.accent))
            Text(text).font(.caption).foregroundColor(ThemeManager.shared.textSec)
        }
    }
}

// MARK: - Home Assistant API

enum SmartHomeAPI {
    // Test kết nối
    static func testConnection() async -> String {
        guard SmartHomeConfig.isConfigured else { return "✗ Chưa nhập URL hoặc token" }
        guard let url = URL(string: "\(SmartHomeConfig.url)/api/") else { return "✗ URL không hợp lệ" }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.addValue("Bearer \(SmartHomeConfig.token)", forHTTPHeaderField: "Authorization")
        do {
            let (_, res) = try await URLSession.shared.data(for: req)
            let code = (res as? HTTPURLResponse)?.statusCode ?? 0
            return code == 200 ? "✓ Kết nối thành công" : "✗ Lỗi HTTP \(code) — kiểm tra lại token"
        } catch {
            return "✗ Không kết nối được: \(error.localizedDescription)"
        }
    }

    // Lấy danh sách entity (đèn, switch, sensor...)
    static func listDevices() async -> String {
        guard SmartHomeConfig.isConfigured else { return "Smart Home chưa được cấu hình. Vào Settings → Smart Home để nhập địa chỉ Home Assistant và token." }
        guard let url = URL(string: "\(SmartHomeConfig.url)/api/states") else { return "URL không hợp lệ." }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.addValue("Bearer \(SmartHomeConfig.token)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let states = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return "Không đọc được danh sách thiết bị."
            }
            // Lọc chỉ light, switch, climate, cover, media_player
            let relevant = states.filter {
                let id = $0["entity_id"] as? String ?? ""
                return id.hasPrefix("light.") || id.hasPrefix("switch.") ||
                       id.hasPrefix("climate.") || id.hasPrefix("cover.") ||
                       id.hasPrefix("media_player.")
            }.prefix(20)
            if relevant.isEmpty { return "Không tìm thấy thiết bị nào." }
            let lines = relevant.map { item -> String in
                let id    = item["entity_id"] as? String ?? ""
                let state = item["state"] as? String ?? "?"
                let name  = (item["attributes"] as? [String: Any])?["friendly_name"] as? String ?? id
                return "\(name) (\(id)): \(state)"
            }
            return "Thiết bị:\n" + lines.joined(separator: "\n")
        } catch {
            return "Lỗi khi lấy danh sách thiết bị: \(error.localizedDescription)"
        }
    }

    // Điều khiển thiết bị
    static func controlDevice(entityId: String, action: String, params: [String: Any] = [:]) async -> String {
        guard SmartHomeConfig.isConfigured else { return "Smart Home chưa được cấu hình." }

        // Map action → HA service
        let (domain, service) = resolveService(entityId: entityId, action: action)
        guard let url = URL(string: "\(SmartHomeConfig.url)/api/services/\(domain)/\(service)") else {
            return "Không tạo được URL."
        }

        var body: [String: Any] = ["entity_id": entityId]
        body.merge(params) { _, new in new }
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return "Lỗi serialize." }

        var req = URLRequest(url: url, timeoutInterval: 8)
        req.httpMethod = "POST"
        req.addValue("Bearer \(SmartHomeConfig.token)", forHTTPHeaderField: "Authorization")
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = bodyData

        do {
            let (_, res) = try await URLSession.shared.data(for: req)
            let code = (res as? HTTPURLResponse)?.statusCode ?? 0
            if code == 200 || code == 201 {
                return "Đã \(action) \(entityId.components(separatedBy: ".").last ?? entityId) thành công."
            }
            return "Lỗi HTTP \(code) khi điều khiển thiết bị."
        } catch {
            return "Lỗi: \(error.localizedDescription)"
        }
    }

    // Lấy trạng thái 1 thiết bị
    static func getDeviceStatus(entityId: String) async -> String {
        guard SmartHomeConfig.isConfigured else { return "Smart Home chưa được cấu hình." }
        guard let url = URL(string: "\(SmartHomeConfig.url)/api/states/\(entityId)") else { return "URL không hợp lệ." }
        var req = URLRequest(url: url, timeoutInterval: 5)
        req.addValue("Bearer \(SmartHomeConfig.token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "Không đọc được trạng thái."
            }
            let state = json["state"] as? String ?? "?"
            let attrs = json["attributes"] as? [String: Any] ?? [:]
            let name  = attrs["friendly_name"] as? String ?? entityId
            var extra = ""
            if let temp = attrs["current_temperature"] { extra += ", nhiệt độ: \(temp)°C" }
            if let bright = attrs["brightness"] as? Int { extra += ", độ sáng: \(bright*100/255)%" }
            return "\(name): \(state)\(extra)"
        } catch {
            return "Lỗi: \(error.localizedDescription)"
        }
    }

    // Giải quyết domain/service từ entity_id và action
    private static func resolveService(entityId: String, action: String) -> (String, String) {
        let domain = entityId.components(separatedBy: ".").first ?? "homeassistant"
        let act = action.lowercased()
        switch domain {
        case "light":
            if act.contains("tắt") || act == "off"  { return ("light", "turn_off") }
            if act.contains("bật") || act == "on"   { return ("light", "turn_on") }
            return ("light", "toggle")
        case "switch":
            if act.contains("tắt") || act == "off"  { return ("switch", "turn_off") }
            if act.contains("bật") || act == "on"   { return ("switch", "turn_on") }
            return ("switch", "toggle")
        case "climate":
            return ("climate", "set_temperature")
        case "cover":
            if act.contains("mở") || act == "open"  { return ("cover", "open_cover") }
            if act.contains("đóng") || act == "close" { return ("cover", "close_cover") }
            return ("cover", "toggle")
        case "media_player":
            if act.contains("tắt") || act == "off"  { return ("media_player", "turn_off") }
            if act.contains("bật") || act == "on"   { return ("media_player", "turn_on") }
            return ("media_player", "toggle")
        default:
            return ("homeassistant", act.contains("tắt") ? "turn_off" : "turn_on")
        }
    }
}
