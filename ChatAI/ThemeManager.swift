import SwiftUI
import UIKit

// ─────────────────────────────────────────────────────────────────────────────
//  ThemeManager.swift
// ─────────────────────────────────────────────────────────────────────────────

final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    // ── Stored ───────────────────────────────────────────────────────────────
    @AppStorage("tm_preset")    var presetID:  String = "fire"
    @AppStorage("tm_ar")        var accentR:   Double = 1.00
    @AppStorage("tm_ag")        var accentG:   Double = 0.34
    @AppStorage("tm_ab")        var accentB:   Double = 0.13
    @AppStorage("tm_bgr")       var bgR:       Double = 0.08
    @AppStorage("tm_bgg")       var bgG:       Double = 0.06
    @AppStorage("tm_bgb")       var bgB:       Double = 0.05
    @AppStorage("has_wall")     var hasWall:   Bool   = false
    @AppStorage("wall_overlay") var wallOvl:   Double = 0.45
    @AppStorage("wall_bright")  var wallBri:   Double = 1.00
    @AppStorage("wall_sat")     var wallSat:   Double = 1.00

    // ── Published ─────────────────────────────────────────────────────────────
    @Published var wallImage:  UIImage? = nil
    @Published var accent:     Color = Color(red:1,green:0.34,blue:0.13)
    @Published var bg:         Color = Color(red:0.08,green:0.06,blue:0.05)
    @Published var surface:    Color = Color(red:0.14,green:0.11,blue:0.09)
    @Published var userBubble: Color = Color(red:1,green:0.34,blue:0.13)
    @Published var aiBubble:   Color = Color(red:0.16,green:0.12,blue:0.10)
    @Published var textPri:    Color = .white
    @Published var textSec:    Color = Color(white:0.60)
    @Published var divider:    Color = Color(white:0.18)

    private init() {
        // Load wallpaper synchronously BEFORE first publish so no flash
        if UserDefaults.standard.bool(forKey: "has_wall") {
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("chatai_wall.jpg")
            _wallImage = Published(initialValue: UIImage(contentsOfFile: url.path))
        }
        rebuild()
    }

    func rebuild() {
        accent     = Color(red: accentR, green: accentG, blue: accentB)
        bg         = Color(red: bgR, green: bgG, blue: bgB)
        surface    = Color(red: min(bgR+0.06,1), green: min(bgG+0.05,1), blue: min(bgB+0.04,1))
        userBubble = accent
        aiBubble   = Color(red: min(bgR+0.08,1), green: min(bgG+0.06,1), blue: min(bgB+0.05,1))
    }

    func apply(preset: AppThemePreset) {
        presetID = preset.id
        accentR = preset.ar; accentG = preset.ag; accentB = preset.ab
        bgR = preset.br;     bgG = preset.bg;     bgB = preset.bb
        rebuild()
    }

    func apply(accent color: Color) {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        accentR = Double(r); accentG = Double(g); accentB = Double(b)
        presetID = "custom"
        rebuild()
    }

    func saveWall(_ image: UIImage) {
        if let data = image.jpegData(compressionQuality: 0.85) {
            try? data.write(to: wallURL)
            hasWall = true
            wallImage = image   // update cache → triggers all View redraws at once
        }
    }

    func removeWall() {
        try? FileManager.default.removeItem(at: wallURL)
        hasWall = false
        wallImage = nil
    }

    private var wallURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chatai_wall.jpg")
    }
}

// MARK: - Presets & palette

struct AppThemePreset: Identifiable {
    let id, name, desc: String
    let gradient: [Color]
    let ar, ag, ab: Double
    let br, bg, bb: Double
}

let appThemePresets: [AppThemePreset] = [
    AppThemePreset(id:"fire",    name:"Hỏa cao cấp",  desc:"Đỏ cam · Than chì",
        gradient:[Color(red:0.70,green:0.15,blue:0.05),Color(red:0.10,green:0.07,blue:0.06)],
        ar:1.00,ag:0.34,ab:0.13, br:0.08,bg:0.06,bb:0.05),
    AppThemePreset(id:"dawn",    name:"Bình minh",     desc:"Cam ấm · Hoàng hôn",
        gradient:[Color(red:0.80,green:0.40,blue:0.10),Color(red:0.12,green:0.09,blue:0.07)],
        ar:1.00,ag:0.60,ab:0.20, br:0.10,bg:0.07,bb:0.05),
    AppThemePreset(id:"nature",  name:"Thiên nhiên",   desc:"Xanh trầm · Than chì",
        gradient:[Color(red:0.05,green:0.35,blue:0.15),Color(red:0.06,green:0.09,blue:0.07)],
        ar:0.18,ag:0.80,ab:0.44, br:0.05,bg:0.08,bb:0.06),
    AppThemePreset(id:"minimal", name:"Tối giản",      desc:"Trung tính · Tinh gọn",
        gradient:[Color(red:0.25,green:0.25,blue:0.28),Color(red:0.08,green:0.08,blue:0.09)],
        ar:0.70,ag:0.70,ab:0.75, br:0.08,bg:0.08,bb:0.09),
]

let accentPalette: [(Double,Double,Double)] = [
    (1.00,0.34,0.13),(1.00,0.60,0.10),(0.95,0.85,0.40),(0.55,0.25,0.95),
    (0.18,0.80,0.44),(0.40,0.40,0.45),(0.75,0.75,0.78),(0.12,0.12,0.14),
    (0.90,0.20,0.30),(1.00,0.50,0.15),(0.95,0.77,0.20),(0.90,0.88,0.55),
    (0.40,0.85,0.95),(0.25,0.55,0.90),(0.15,0.30,0.75),(0.55,0.25,0.70),
    (0.75,0.30,0.60),(0.88,0.35,0.45),(0.20,0.55,0.25),(0.40,0.60,0.20),
    (0.55,0.70,0.10),(0.10,0.70,0.55),(0.05,0.65,0.65),(0.95,0.95,0.95),
]
