import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
//  RobotFaceView  –  cute robot companion, fully code-drawn
//  Geometry ported 1-to-1 from the Python preview renderer.
//
//  Public API
//    RobotFaceView(expression:, speakingLevel:, isListening:, onTap:)
//    RobotFacePreviewView()          ← settings / gallery screen
//    RobotFaceExpression (enum)
//    RobotFaceMood.guess(from:)      ← keyword → expression
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Expression enum

enum RobotFaceExpression: String, CaseIterable, Identifiable {
    case idle, listening, thinking, speaking
    case happy, surprised, confused, sad, angry, sleepy
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
        }
    }
}

// MARK: - Expression parameters

struct RobotParams {
    var eyeOpen: CGFloat  = 1.0   // 0 = fully closed … 1 = normal … 1.2 = wide
    var eyeSmile: CGFloat = 0.0   // 0 = round … 1 = arc smile
    var lidAmount: CGFloat = 0.0  // 0 = none … 1 = fully lidded
    var lidTilt:  CGFloat = 0.0   // -1 sad tilt … +1 angry tilt
    var lookX:    CGFloat = 0.0
    var lookY:    CGFloat = 0.0
    var rightEyeScale: CGFloat = 1.0
    var blush:    CGFloat = 1.0
    var mouthKind: MouthKind = .omega
    var tear:     Bool = false

    enum MouthKind { case omega, smile, frown, flat, wavy, tiny, open, o }

    // --- Lerp ---
    static func lerp(_ a: RobotParams, _ b: RobotParams, _ t: CGFloat) -> RobotParams {
        func m(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * t }
        var r = RobotParams()
        r.eyeOpen       = m(a.eyeOpen, b.eyeOpen)
        r.eyeSmile      = m(a.eyeSmile, b.eyeSmile)
        r.lidAmount     = m(a.lidAmount, b.lidAmount)
        r.lidTilt       = m(a.lidTilt, b.lidTilt)
        r.lookX         = m(a.lookX, b.lookX)
        r.lookY         = m(a.lookY, b.lookY)
        r.rightEyeScale = m(a.rightEyeScale, b.rightEyeScale)
        r.blush         = m(a.blush, b.blush)
        r.tear          = t < 0.5 ? a.tear : b.tear
        r.mouthKind     = t < 0.5 ? a.mouthKind : b.mouthKind
        return r
    }

    // --- Factory ---
    static func of(_ e: RobotFaceExpression) -> RobotParams {
        var p = RobotParams()
        switch e {
        case .idle:      break
        case .listening: p.eyeOpen = 1.1
        case .thinking:  p.lookX = 0.75; p.lookY = -0.65; p.mouthKind = .flat
        case .speaking:  p.eyeSmile = 1.0; p.mouthKind = .open
        case .happy:     p.eyeSmile = 1.0; p.mouthKind = .smile; p.blush = 1.4
        case .surprised: p.eyeOpen = 1.18; p.mouthKind = .o
        case .confused:  p.rightEyeScale = 0.82; p.lookX = 0.5; p.lookY = -0.2; p.mouthKind = .wavy
        case .sad:       p.lidAmount = 0.30; p.lidTilt = -0.55; p.lookY = 0.25; p.mouthKind = .frown; p.blush = 0.35; p.tear = true
        case .angry:     p.lidAmount = 0.42; p.lidTilt = 0.65; p.mouthKind = .frown; p.blush = 0.0
        case .sleepy:    p.lidAmount = 0.64; p.mouthKind = .tiny
        }
        return p
    }
}

// MARK: - Smooth transition (no Timer – uses TimelineView's date)

final class RobotTransition: ObservableObject {
    private var from = RobotParams.of(.idle)
    private var to   = RobotParams.of(.idle)
    private var start: Date = .distantPast
    private let dur: TimeInterval = 0.32

    func snap(_ e: RobotFaceExpression) {
        let p = RobotParams.of(e)
        from = p; to = p; start = .distantPast
    }
    func begin(_ e: RobotFaceExpression) {
        from = params(at: Date()); to = RobotParams.of(e); start = Date()
    }
    func params(at date: Date) -> RobotParams {
        let raw = min(1, max(0, CGFloat(date.timeIntervalSince(start) / dur)))
        let t   = 1 - pow(1 - raw, 3)          // ease-out cubic
        return RobotParams.lerp(from, to, t)
    }
}

// MARK: - Main view

struct RobotFaceView: View {
    var expression: RobotFaceExpression
    /// Returns 0…1, called with the current animation date
    var speakingLevel: (Date) -> CGFloat = { _ in 0 }
    var isListening: Bool = false
    var onTap: (() -> Void)? = nil

    @StateObject private var tr = RobotTransition()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 40)) { tl in
            let p     = tr.params(at: tl.date)
            let level = speakingLevel(tl.date)
            let t     = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                RobotRenderer.draw(&ctx, size: size, params: p,
                                   level: level, t: t,
                                   expression: expression,
                                   listening: isListening)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .onAppear            { tr.snap(expression) }
        .onChange(of: expression) { tr.begin($0) }
    }
}

// MARK: - Renderer

enum RobotRenderer {
    // palette
    static let cyan      = Color(red: 0.24, green: 0.90, blue: 1.00)
    static let cyanSoft  = Color(red: 0.47, green: 0.96, blue: 1.00)
    static let pink      = Color(red: 1.00, green: 0.55, blue: 0.78)
    static let pinkPale  = Color(red: 1.00, green: 0.80, blue: 0.91)
    static let pinkDark  = Color(red: 1.00, green: 0.47, blue: 0.74)
    static let navy      = Color(red: 0.04, green: 0.05, blue: 0.09)
    static let screenBg  = Color(red: 0.07, green: 0.09, blue: 0.18)
    static let blushCol  = Color(red: 1.00, green: 0.39, blue: 0.63)
    static let tearCol   = Color(red: 0.55, green: 0.92, blue: 1.00)
    static let tongue    = Color(red: 1.00, green: 0.43, blue: 0.65)

    static func draw(_ ctx: inout GraphicsContext, size: CGSize,
                     params p: RobotParams, level: CGFloat, t: Double,
                     expression: RobotFaceExpression, listening: Bool) {

        let S   = min(size.width, size.height)
        let cx  = size.width / 2
        let cy  = size.height / 2
        // breathe + speaking bob
        let breathe = 1 + 0.012 * sin(t * 1.5)
        let R   = S * 0.40 * breathe
        let bobY: CGFloat = expression == .speaking
            ? S * 0.015 * CGFloat(abs(sin(t * 8))) : 0
        let baseY = cy + bobY

        func pt(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
            CGPoint(x: cx + nx * S, y: baseY + ny * S)
        }
        func ptH(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {   // centred on head
            CGPoint(x: cx + nx * R, y: baseY + ny * R)
        }

        let speak = CGFloat(pow(Double(min(1, max(0, level))), 0.8))

        drawWings(   &ctx, pt, t, S)
        drawAntennae(&ctx, pt, t, S)
        drawHelmet(  &ctx, ptH, cx, baseY, R, S)
        drawScreen(  &ctx, ptH, cx, baseY, S)
        drawEars(    &ctx, pt, t, S)
        drawFace(    &ctx, pt, cx, baseY, S, params: p, speak: speak, t: t, expression: expression)
        if listening { drawListenRing(&ctx, cx: cx, cy: baseY, R: R, t: t) }
    }

    // ── Quad Bézier helper ──────────────────────────────────────────────────
    static func quad(_ p0: CGPoint, _ cp: CGPoint, _ p1: CGPoint, n: Int = 28) -> Path {
        var path = Path()
        path.move(to: p0)
        path.addQuadCurve(to: p1, control: cp)
        return path
    }

    static func quadPts(_ p0: CGPoint, _ cp: CGPoint, _ p1: CGPoint, n: Int = 32) -> [CGPoint] {
        (0...n).map { i in
            let tt = CGFloat(i) / CGFloat(n)
            let xt = pow(1-tt,2)*p0.x + 2*(1-tt)*tt*cp.x + tt*tt*p1.x
            let yt = pow(1-tt,2)*p0.y + 2*(1-tt)*tt*cp.y + tt*tt*p1.y
            return CGPoint(x: xt, y: yt)
        }
    }

    // ── Superellipse ─────────────────────────────────────────────────────────
    static func superellipsePath(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat,
                                  n: Double = 2.35, N: Int = 120) -> Path {
        var pts: [CGPoint] = []
        for i in 0..<N {
            let t = 2 * .pi * Double(i) / Double(N)
            let c = cos(t), s = sin(t)
            let x = cx + rx * CGFloat(c < 0 ? -pow(-c, 2/n) : pow(c, 2/n))
            let y = cy + ry * CGFloat(s < 0 ? -pow(-s, 2/n) : pow(s, 2/n))
            pts.append(CGPoint(x: x, y: y))
        }
        var path = Path()
        path.addLines(pts)
        path.closeSubpath()
        return path
    }

    // ── Leaf (wing) shape ────────────────────────────────────────────────────
    static func leafPath(root: CGPoint, angleDeg: CGFloat, length: CGFloat,
                          halfWidth: CGFloat, N: Int = 44) -> Path {
        let a   = CGFloat(angleDeg * .pi / 180)
        let dx  = cos(a), dy = sin(a)
        let nx  = -dy,    ny = dx
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0...N {
            let tt = CGFloat(i) / CGFloat(N)
            let w  = halfWidth * pow(sin(.pi * pow(tt, 0.85)), 0.9) / 2
            let ppx = root.x + dx * length * tt
            let ppy = root.y + dy * length * tt
            left .append(CGPoint(x: ppx + nx * w, y: ppy + ny * w))
            right.append(CGPoint(x: ppx - nx * w, y: ppy - ny * w))
        }
        var path = Path()
        path.addLines(left)
        path.addLines(right.reversed())
        path.closeSubpath()
        return path
    }

    // ── Glow helper ──────────────────────────────────────────────────────────
    static func glow(_ ctx: inout GraphicsContext, _ path: Path,
                      color: Color, blurR: CGFloat, alpha: Double = 1.0) {
        var layer = ctx
        layer.addFilter(.blur(radius: blurR))
        layer.fill(path, with: .color(color.opacity(alpha)))
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  WINGS
    // ─────────────────────────────────────────────────────────────────────────
    static func drawWings(_ ctx: inout GraphicsContext,
                           _ pt: (CGFloat,CGFloat)->CGPoint, _ t: Double, _ S: CGFloat) {
        let wings: [(CGFloat,CGFloat,CGFloat,CGFloat,CGFloat,Int)] = [
            // rootX rootY angleDeg length halfWidth side(-1L,1R)
            (0.20, 0.52, 238, 0.40, 0.21, -1),
            (0.23, 0.68, 152, 0.27, 0.13, -1),
            (0.80, 0.52,  -58, 0.40, 0.21,  1),
            (0.77, 0.68,   28, 0.27, 0.13,  1),
        ]
        let flap = CGFloat(sin(t * 3.0)) * 0.004
        for (rx0, ry0, ang, ln, hw, _) in wings {
            let root = pt(rx0 - 0.5, ry0 - 0.5)
            let path = leafPath(root: root, angleDeg: ang,
                                length: ln * S, halfWidth: hw * S * (1 + flap))
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: S * 0.012))
                layer.fill(path, with: .color(Color(red:0.7,green:0.85,blue:1).opacity(0.22)))
            }
            ctx.fill(path, with: .linearGradient(
                Gradient(colors: [
                    Color(red:0.75,green:0.93,blue:1.00).opacity(0.72),
                    Color(red:0.88,green:0.88,blue:1.00).opacity(0.62),
                    Color(red:1.00,green:0.78,blue:0.91).opacity(0.62)]),
                startPoint: pt(-0.5, -0.40), endPoint: pt(-0.5, 0.40)))
            ctx.stroke(path, with: .color(.white.opacity(0.55)),
                       style: StrokeStyle(lineWidth: S * 0.005, lineJoin: .round))
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  ANTENNAE
    // ─────────────────────────────────────────────────────────────────────────
    static func drawAntennae(_ ctx: inout GraphicsContext,
                              _ pt: (CGFloat,CGFloat)->CGPoint, _ t: Double, _ S: CGFloat) {
        let stems: [(CGFloat,CGFloat,CGFloat,CGFloat)] = [
            (0.36-0.5, 0.26-0.5, 0.265-0.5, 0.085-0.5),
            (0.64-0.5, 0.26-0.5, 0.735-0.5, 0.085-0.5),
        ]
        for (bx,by,tx,ty) in stems {
            var p = Path(); p.move(to: pt(bx,by)); p.addLine(to: pt(tx,ty))
            ctx.stroke(p, with: .color(pink.opacity(0.9)),
                       style: StrokeStyle(lineWidth: S * 0.011, lineCap: .round))
            let c = pt(tx, ty), r = S * 0.036
            let sway = CGFloat(sin(t * 2.2 + (tx > 0 ? 1 : 0))) * S * 0.005
            let bc = CGPoint(x: c.x + sway, y: c.y)
            let rect = CGRect(x: bc.x-r, y: bc.y-r, width: r*2, height: r*2)
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: S*0.022))
                l.fill(Path(ellipseIn: rect.insetBy(dx: -r*0.5, dy: -r*0.5)),
                       with: .color(pink.opacity(0.7)))
            }
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [pinkPale, pinkDark]),
                center: CGPoint(x: bc.x-r*0.3, y: bc.y-r*0.3),
                startRadius: 0, endRadius: r * 1.6))
            let hr = r * 0.30
            ctx.fill(Path(ellipseIn: CGRect(x: bc.x-r*0.55, y: bc.y-r*0.65, width: hr, height: hr*0.7)),
                     with: .color(.white.opacity(0.85)))
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  HELMET
    // ─────────────────────────────────────────────────────────────────────────
    static func drawHelmet(_ ctx: inout GraphicsContext,
                            _ ptH: (CGFloat,CGFloat)->CGPoint,
                            _ cx: CGFloat, _ cy: CGFloat, _ R: CGFloat, _ S: CGFloat) {
        let hx = cx, hy = cy
        let hrx = R * 0.97, hry = R * 0.73
        let hpath = superellipsePath(cx: hx, cy: hy, rx: hrx, ry: hry, n: 2.35)
        // shadow
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: R*0.06))
            var sp = superellipsePath(cx: hx, cy: hy + R*0.04, rx: hrx, ry: hry, n: 2.35)
            l.fill(sp, with: .color(pink.opacity(0.35)))
        }
        // body
        ctx.fill(hpath, with: .linearGradient(
            Gradient(colors: [Color(red:1,green:1,blue:1), Color(red:1,green:0.96,blue:0.98), Color(red:1,green:0.82,blue:0.91)]),
            startPoint: ptH(0, -0.73), endPoint: ptH(0, 0.73)))
        // rim glow
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: S*0.010))
            l.stroke(hpath, with: .color(pink.opacity(0.60)), style: StrokeStyle(lineWidth: S*0.025))
        }
        ctx.stroke(hpath, with: .color(pink.opacity(0.75)), style: StrokeStyle(lineWidth: S*0.012))
        // top gloss arc
        var gloss = Path()
        let gr = hrx * 0.95
        gloss.addArc(center: CGPoint(x: hx, y: hy), radius: gr,
                     startAngle: .degrees(200), endAngle: .degrees(340), clockwise: false)
        ctx.stroke(gloss, with: .color(.white.opacity(0.40)),
                   style: StrokeStyle(lineWidth: S*0.015, lineCap: .round))
        // top centre seam
        var seam = Path()
        seam.move(to: CGPoint(x: hx, y: hy - hry))
        seam.addLine(to: CGPoint(x: hx, y: hy - hry + R*0.12))
        ctx.stroke(seam, with: .color(Color(red:0.74,green:0.84,blue:1).opacity(0.50)),
                   style: StrokeStyle(lineWidth: S*0.006, lineCap: .round))
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  SCREEN SURROUND + SCREEN
    // ─────────────────────────────────────────────────────────────────────────
    static func drawScreen(_ ctx: inout GraphicsContext,
                            _ ptH: (CGFloat,CGFloat)->CGPoint,
                            _ cx: CGFloat, _ cy: CGFloat, _ S: CGFloat) {
        let u = S * 0.33
        // surround (slightly bigger)
        let surr = superellipsePath(cx: cx, cy: cy, rx: u*1.08, ry: u*0.685, n: 2.7)
        ctx.fill(surr, with: .linearGradient(
            Gradient(colors: [Color(red:1,green:0.80,blue:0.91), Color(red:1,green:0.59,blue:0.80)]),
            startPoint: ptH(0,-0.70), endPoint: ptH(0,0.70)))
        // screen glass
        let scr = superellipsePath(cx: cx, cy: cy, rx: u, ry: u*0.622, n: 2.7)
        ctx.fill(scr, with: .linearGradient(
            Gradient(colors: [Color(red:0.07,green:0.09,blue:0.18), navy]),
            startPoint: ptH(0,-0.62), endPoint: ptH(0,0.62)))
        // glass reflection arc
        var ref = Path()
        ref.addArc(center: CGPoint(x: cx, y: cy), radius: u * 0.90,
                   startAngle: .degrees(205), endAngle: .degrees(255), clockwise: false)
        ctx.stroke(ref, with: .color(.white.opacity(0.25)),
                   style: StrokeStyle(lineWidth: S*0.018, lineCap: .round))
        // small corner glints
        for (ox,oy) in [(-u*0.78+cx, cy-u*0.46), (-u*0.80+cx, cy-u*0.30)] {
            let dr = ox < cx ? S*0.012 : S*0.008
            ctx.fill(Path(ellipseIn: CGRect(x: ox-dr, y: oy-dr, width: dr*2, height: dr*2)),
                     with: .color(.white.opacity(0.38)))
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  EARS
    // ─────────────────────────────────────────────────────────────────────────
    static func drawEars(_ ctx: inout GraphicsContext,
                          _ pt: (CGFloat,CGFloat)->CGPoint, _ t: Double, _ S: CGFloat) {
        for sign: CGFloat in [-1, 1] {
            let c   = pt(0.5 * sign, 0.085)    // (0.5+sign*0.43 - 0.5)*S offset
            let cx_ = c.x + sign * S * (0.43 - 0.5)
            let cy_ = c.y
            let ec  = CGPoint(x: cx_ + sign * S * 0.43, y: cy_)
            let r   = S * 0.074

            // glow
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: S*0.022))
                l.fill(Path(ellipseIn: CGRect(x: ec.x-r*1.1, y: ec.y-r*1.1, width: r*2.2, height: r*2.2)),
                       with: .color(pink.opacity(0.55)))
            }
            // body
            ctx.fill(Path(ellipseIn: CGRect(x: ec.x-r, y: ec.y-r, width: r*2, height: r*2)),
                     with: .radialGradient(
                        Gradient(colors: [Color(red:1,green:0.80,blue:0.90), pinkDark]),
                        center: CGPoint(x: ec.x - r*0.3, y: ec.y - r*0.4),
                        startRadius: 0, endRadius: r*1.7))
            // inner disc
            let ir = r * 0.64
            let iRect = CGRect(x: ec.x-ir, y: ec.y-ir, width: ir*2, height: ir*2)
            ctx.fill(Path(ellipseIn: iRect), with: .color(Color(red:1,green:0.91,blue:0.96)))
            if sign < 0 {
                // 5-dot pattern (left ear, cross-like shape)
                let dotR = ir * 0.22
                for k in 0..<5 {
                    let ang = CGFloat(k) * 2 * .pi / 5 - .pi / 2
                    let dpx = ec.x + cos(ang) * ir * 0.38
                    let dpy = ec.y - sin(ang) * ir * 0.38
                    ctx.fill(Path(ellipseIn: CGRect(x: dpx-dotR, y: dpy-dotR, width: dotR*2, height: dotR*2)),
                             with: .color(.white))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: ec.x-dotR*0.5, y: ec.y-dotR*0.5, width: dotR, height: dotR)),
                         with: .color(pink))
            } else {
                // cyan LED circle (right ear)
                let led = ir * 0.50
                ctx.fill(Path(ellipseIn: CGRect(x: ec.x-led, y: ec.y-led, width: led*2, height: led*2)),
                         with: .color(cyan.opacity(0.90)))
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: S*0.009))
                    l.fill(Path(ellipseIn: CGRect(x: ec.x-led*1.2, y: ec.y-led*1.2, width: led*2.4, height: led*2.4)),
                           with: .color(cyan.opacity(0.60)))
                }
            }
            // cyan LED arc
            var arc = Path()
            arc.addArc(center: ec, radius: r*0.86,
                       startAngle: .degrees(20), endAngle: .degrees(90), clockwise: false)
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: S*0.006))
                l.stroke(arc, with: .color(cyan), style: StrokeStyle(lineWidth: S*0.010))
            }
            ctx.stroke(arc, with: .color(cyan), style: StrokeStyle(lineWidth: S*0.007))
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  FACE: blush + eyes + mouth + extras
    // ─────────────────────────────────────────────────────────────────────────
    static func drawFace(_ ctx: inout GraphicsContext,
                          _ pt: (CGFloat,CGFloat)->CGPoint,
                          _ cx: CGFloat, _ cy: CGFloat, _ S: CGFloat,
                          params p: RobotParams, speak: CGFloat,
                          t: Double, expression: RobotFaceExpression) {

        let u = S * 0.33    // screen half-width

        // --- blink timing ---
        func blink() -> CGFloat {
            func bump(_ cycle: Double, _ offset: Double, _ len: Double) -> Double {
                let phase = (t + offset).truncatingRemainder(dividingBy: cycle)
                return phase < len ? sin(phase / len * .pi) : 0
            }
            if expression == .sleepy { return CGFloat(bump(4.5, 0, 1.4)) }
            return CGFloat(max(bump(3.7, 0, 0.17), bump(5.9, 1.9, 0.17)))
        }
        let blinkAmt = blink()

        // --- look drift ---
        let wander: Double = expression == .sleepy ? 0.1 :
                             expression == .listening ? 0.2 : 0.9
        let driftX = CGFloat(wander * (0.35*sin(t*0.37) + 0.2*sin(t*0.91+1.3)))
        let driftY = CGFloat(wander * 0.2 * sin(t*0.53+0.4))
        let lx = min(1, max(-1, p.lookX + driftX))
        let ly = min(1, max(-1, p.lookY + driftY))

        // --- blush ---
        if p.blush > 0.01 {
            for sign: CGFloat in [-1, 1] {
                let bx = cx + sign * 0.74 * u
                let by = cy + 0.36 * u
                let bw = 0.13 * u, bh = 0.065 * u
                let br = CGRect(x: bx-bw, y: by-bh, width: bw*2, height: bh*2)
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: S*0.009))
                    l.fill(Path(ellipseIn: br), with: .color(blushCol.opacity(0.80 * Double(p.blush))))
                }
            }
        }

        // --- eyes ---
        for (sign, scale): (CGFloat, CGFloat) in [(-1, 1.0), (1, p.rightEyeScale)] {
            let ecy = cy - 0.03 * u
            let ecx = cx + sign * 0.54 * u
            let rx  = 0.265 * u * scale
            var ry  = 0.36  * u * scale * p.eyeOpen
            ry = max(ry, S * 0.012)

            let lookOffX = lx * 0.05 * u
            let lookOffY = ly * 0.05 * u
            let ex_  = ecx + lookOffX
            let ey_  = ecy + lookOffY

            ctx.drawLayer { eyeCtx in
                if p.eyeSmile > 0.5 {
                    // arc smile eye
                    let pts = quadPts(CGPoint(x: ex_-rx*1.0, y: ey_+ry*0.35),
                                      CGPoint(x: ex_, y: ey_-ry*0.95),
                                      CGPoint(x: ex_+rx*1.0, y: ey_+ry*0.35))
                    var arcPath = Path(); arcPath.addLines(pts)
                    eyeCtx.drawLayer { l in
                        l.addFilter(.blur(radius: S*0.014))
                        l.stroke(arcPath, with: .color(cyan), style: StrokeStyle(lineWidth: S*0.040, lineCap:.round))
                    }
                    eyeCtx.stroke(arcPath, with: .color(cyan), style: StrokeStyle(lineWidth: S*0.034, lineCap:.round))
                    return
                }
                // --- round eye ---
                // outer ring (cyan)
                let ringRect = CGRect(x: ex_-rx, y: ey_-ry, width: rx*2, height: ry*2)
                eyeCtx.fill(Path(ellipseIn: ringRect), with: .radialGradient(
                    Gradient(colors: [Color(red:0.31,green:0.93,blue:1), Color(red:0.12,green:0.80,blue:0.94)]),
                    center: CGPoint(x: ex_, y: ey_), startRadius: 0, endRadius: max(rx,ry)))
                // inner dark iris
                let irx = rx*0.76, iry = ry*0.80
                let ix = ex_ + lookOffX*0.6, iy = ey_ + lookOffY*0.6
                let irisRect = CGRect(x: ix-irx, y: iy-iry, width: irx*2, height: iry*2)
                eyeCtx.fill(Path(ellipseIn: irisRect), with: .radialGradient(
                    Gradient(colors: [Color(red:0.01,green:0.10,blue:0.14),
                                      Color(red:0.02,green:0.23,blue:0.28),
                                      Color(red:0.07,green:0.49,blue:0.57)]),
                    center: CGPoint(x: ix, y: iy), startRadius: 0, endRadius: max(irx,iry)))
                // highlights
                if p.eyeOpen > 0.45 {
                    let h1r = rx*0.27
                    let h1  = CGPoint(x: ix-irx*0.32+lookOffX*0.4, y: iy-iry*0.36+lookOffY*0.4)
                    eyeCtx.fill(Path(ellipseIn: CGRect(x: h1.x-h1r, y: h1.y-h1r, width: h1r*2, height: h1r*2)),
                                with: .color(.white.opacity(0.95)))
                    let h2r = rx*0.12
                    let h2  = CGPoint(x: ix+irx*0.36+lookOffX*0.4, y: iy+iry*0.36+lookOffY*0.4)
                    eyeCtx.fill(Path(ellipseIn: CGRect(x: h2.x-h2r, y: h2.y-h2r, width: h2r*2, height: h2r*2)),
                                with: .color(Color(red:0.82,green:0.98,blue:1).opacity(0.90)))
                }
                // lid (blink + expression lid)
                let totalLid = min(1, max(p.lidAmount, blinkAmt))
                if totalLid > 0.01 {
                    let d_in: CGFloat = sign > 0 ? -1 : 1
                    let topOfEye = ey_ - ry
                    let lidY     = topOfEye + totalLid * 2 * ry
                    func lidYAt(_ x: CGFloat) -> CGFloat {
                        lidY + p.lidTilt * ry * 0.9 * ((x - ex_) * d_in / rx)
                    }
                    let leftX  = ex_ - rx * 1.6, rightX = ex_ + rx * 1.6
                    var clip = Path()
                    clip.move(to: CGPoint(x: leftX,  y: lidYAt(leftX)  - ry*3))
                    clip.addLine(to: CGPoint(x: rightX, y: lidYAt(rightX) - ry*3))
                    clip.addLine(to: CGPoint(x: rightX, y: lidYAt(rightX)))
                    clip.addLine(to: CGPoint(x: leftX,  y: lidYAt(leftX)))
                    clip.closeSubpath()
                    eyeCtx.clip(to: Path(ellipseIn: ringRect), options: .inverse)
                    eyeCtx.fill(clip, with: .color(.clear))   // punch-out via clip
                    // lid edge glow
                    var edge = Path()
                    edge.move(to: CGPoint(x: leftX, y: lidYAt(leftX)))
                    edge.addLine(to: CGPoint(x: rightX, y: lidYAt(rightX)))
                    eyeCtx.drawLayer { l in
                        l.addFilter(.blur(radius: S*0.008))
                        l.stroke(edge, with: .color(cyanSoft.opacity(0.85)),
                                 style: StrokeStyle(lineWidth: S*0.011, lineCap:.round))
                    }
                    eyeCtx.stroke(edge, with: .color(cyanSoft),
                                  style: StrokeStyle(lineWidth: S*0.007, lineCap:.round))
                }
                // upper lash arc (only when not fully lidded)
                if totalLid < 0.15 {
                    let a0: CGFloat = sign < 0 ? 198 : 222
                    let a1: CGFloat = sign < 0 ? 342 : 318
                    var lash = Path()
                    lash.addArc(center: CGPoint(x: ex_, y: ey_ - ry*0.02),
                                radius: (rx*1.18 + ry*1.12)/2,
                                startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: sign < 0)
                    eyeCtx.drawLayer { l in
                        l.addFilter(.blur(radius: S*0.010))
                        l.stroke(lash, with: .color(cyan.opacity(0.80)),
                                 style: StrokeStyle(lineWidth: S*0.028, lineCap:.round))
                    }
                    eyeCtx.stroke(lash, with: .color(cyan),
                                  style: StrokeStyle(lineWidth: S*0.024, lineCap:.round))
                }
                // glow around eye
                eyeCtx.drawLayer { l in
                    l.addFilter(.blur(radius: S*0.016))
                    l.fill(Path(ellipseIn: ringRect.insetBy(dx: -S*0.004, dy: -S*0.004)),
                           with: .color(cyan.opacity(0.55)))
                }
                // tear drop (sad)
                if p.tear && sign > 0 {
                    let tx = ex_ + rx*0.2, ty_ = ey_ + ry*1.25
                    let tr = Path(ellipseIn: CGRect(x:tx-S*0.016, y:ty_-S*0.026, width:S*0.032, height:S*0.058))
                    ctx.drawLayer { l in
                        l.addFilter(.blur(radius: S*0.008))
                        l.fill(tr, with: .color(tearCol.opacity(0.9)))
                    }
                    ctx.fill(tr, with: .color(tearCol.opacity(0.85)))
                }
            }
        }

        // --- mouth ---
        let my  = cy + 0.20 * u
        let mw  = S * 0.026
        let mop = max(p.mouthOpen, speak * 0.85)
        var mpath = Path()
        switch p.mouthKind {
        case .omega:
            let hw = 0.10 * u
            mpath.addLines(quadPts(CGPoint(x:cx-hw, y:my), CGPoint(x:cx-hw*0.5, y:my+0.11*u), CGPoint(x:cx, y:my)))
            mpath.addLines(quadPts(CGPoint(x:cx, y:my), CGPoint(x:cx+hw*0.5, y:my+0.11*u), CGPoint(x:cx+hw, y:my)))
        case .smile:
            let hw = 0.17 * u
            mpath = quad(CGPoint(x:cx-hw, y:my-0.01*u), CGPoint(x:cx, y:my+0.26*u), CGPoint(x:cx+hw, y:my-0.01*u))
        case .frown:
            let hw = 0.11 * u
            mpath = quad(CGPoint(x:cx-hw, y:my+0.05*u), CGPoint(x:cx, y:my-0.10*u), CGPoint(x:cx+hw, y:my+0.05*u))
        case .flat:
            mpath.move(to: CGPoint(x:cx-0.07*u, y:my+0.03*u))
            mpath.addLine(to: CGPoint(x:cx+0.07*u, y:my))
        case .wavy:
            var pts:[CGPoint] = []
            for i in 0...40 {
                let tt = CGFloat(i)/40
                pts.append(CGPoint(x: cx - 0.13*u + 0.26*u*tt,
                                   y: my + 0.025*u + 0.04*u * CGFloat(sin(tt * 2 * .pi * 1.5))))
            }
            mpath.addLines(pts)
        case .tiny:
            mpath = quad(CGPoint(x:cx-0.05*u, y:my+0.02*u), CGPoint(x:cx, y:my+0.10*u), CGPoint(x:cx+0.05*u, y:my+0.02*u))
        case .open:
            let hw = 0.115 * u
            let top = CGPoint(x:cx-hw, y:my-0.02*u)
            let bot = CGPoint(x:cx+hw, y:my-0.02*u)
            var p1 = Path()
            p1.addLines(quadPts(top, CGPoint(x:cx, y:my+0.03*u), bot))
            p1.addLines(quadPts(bot, CGPoint(x:cx, y:my+mop*0.30*u), top))
            p1.closeSubpath()
            // fill inner + tongue
            ctx.fill(p1, with: .color(Color(red:0.20,green:0.05,blue:0.14)))
            if mop > 0.25 {
                let ty_ = my + mop*0.22*u
                ctx.fill(Path(ellipseIn: CGRect(x:cx-0.065*u, y:ty_-0.025*u, width:0.13*u, height:0.075*u)),
                         with: .color(tongue.opacity(0.90)))
            }
            mpath = p1
        case .o:
            let oc = CGPoint(x:cx, y:my+0.075*u)
            let oxr = 0.06*u, oyr = 0.085*u
            ctx.fill(Path(ellipseIn: CGRect(x:oc.x-oxr, y:oc.y-oyr, width:oxr*2, height:oyr*2)),
                     with: .color(Color(red:0.20,green:0.05,blue:0.14)))
            mpath = Path(ellipseIn: CGRect(x:oc.x-oxr, y:oc.y-oyr, width:oxr*2, height:oyr*2))
        }

        ctx.drawLayer { l in
            l.addFilter(.blur(radius: S*0.010))
            l.stroke(mpath, with: .color(cyan.opacity(0.9)),
                     style: StrokeStyle(lineWidth: mw*1.5, lineCap:.round, lineJoin:.round))
        }
        ctx.stroke(mpath, with: .color(cyan),
                   style: StrokeStyle(lineWidth: mw, lineCap:.round, lineJoin:.round))

        // --- expression extras ---
        switch expression {
        case .sleepy:
            for i in 0..<3 {
                let phase = CGFloat((t * 0.45 + Double(i)/3.0).truncatingRemainder(dividingBy: 1.0))
                let fx = cx + S*0.38 + phase * S*0.10
                let fy = cy - S*0.27 - phase * S*0.27
                let alpha = Double(sin(phase * .pi))
                let size_ = S*(0.06 + 0.04*phase)
                ctx.draw(Text("z").font(.system(size: size_, weight:.bold, design:.rounded))
                    .foregroundColor(cyan.opacity(alpha * 0.9)), at: CGPoint(x:fx, y:fy))
            }
        case .thinking:
            for i in 0..<3 {
                let bounce = CGFloat(sin(t*4.0 + Double(i)*0.9))
                let fx = cx + S*(0.30 + 0.065*CGFloat(i))
                let fy = cy - S*(0.25) + S*0.015*bounce - S*0.024*CGFloat(i)
                let dr = S*0.018
                ctx.fill(Path(ellipseIn: CGRect(x:fx-dr, y:fy-dr, width:dr*2, height:dr*2)),
                         with: .color(cyan.opacity(0.85)))
            }
        case .sad:
            let phase = CGFloat((t*0.45).truncatingRemainder(dividingBy: 1.0))
            let tx_ = cx - S*0.12
            let ty_ = cy + S*(0.05 + 0.14*phase)
            let alpha = Double(sin(phase * .pi)) * 0.9
            let tr2 = Path(ellipseIn: CGRect(x:tx_-S*0.016, y:ty_-S*0.026, width:S*0.032, height:S*0.058))
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: S*0.008))
                l.fill(tr2, with: .color(tearCol.opacity(alpha)))
            }
            ctx.fill(tr2, with: .color(tearCol.opacity(alpha)))
        case .happy:
            let sc_ = CGPoint(x:cx+S*0.34, y:cy-S*0.22)
            let r1 = S*0.034, r2 = S*0.010
            var star = Path()
            for k in 0..<8 {
                let ang = CGFloat(k)*2*.pi/8 - .pi/2
                let rr  = k%2==0 ? r1 : r2
                star.addLine(to: CGPoint(x:sc_.x+cos(ang)*rr, y:sc_.y+sin(ang)*rr))
            }
            star.closeSubpath()
            ctx.fill(star, with: .color(cyan.opacity(0.90)))
        case .confused:
            ctx.draw(Text("?").font(.system(size:S*0.11, weight:.bold)).foregroundColor(cyan.opacity(0.90)),
                     at: CGPoint(x:cx+S*0.31, y:cy-S*0.22))
        case .angry:
            let ac = CGPoint(x:cx+S*0.31, y:cy-S*0.22)
            let redA = Color(red:1,green:0.27,blue:0.39)
            for k in 0..<4 {
                let ang = CGFloat(k)*2*.pi/4 + .pi/4
                let tip = CGPoint(x: ac.x + cos(ang)*S*0.026, y: ac.y + sin(ang)*S*0.026)
                var line = Path()
                line.move(to: CGPoint(x:tip.x+cos(ang+1.1)*S*0.024, y:tip.y+sin(ang+1.1)*S*0.024))
                line.addLine(to: CGPoint(x:tip.x+cos(ang-1.1)*S*0.024, y:tip.y+sin(ang-1.1)*S*0.024))
                ctx.stroke(line, with: .color(redA.opacity(0.85)),
                           style: StrokeStyle(lineWidth: S*0.009, lineCap:.round))
            }
        case .listening:
            for sign: CGFloat in [-1,1] {
                let ec = CGPoint(x: cx + sign * S * 0.43, y: cy)
                for rr in [S*0.105, S*0.135] {
                    let a0: Double = sign < 0 ? 150 : -30
                    let a1: Double = sign < 0 ? 210 :  30
                    var arc = Path()
                    arc.addArc(center: ec, radius: rr, startAngle: .degrees(a0), endAngle: .degrees(a1), clockwise: false)
                    ctx.drawLayer { l in
                        l.addFilter(.blur(radius: S*0.007))
                        l.stroke(arc, with: .color(cyanSoft.opacity(0.70)), style: StrokeStyle(lineWidth: S*0.009, lineCap:.round))
                    }
                    ctx.stroke(arc, with: .color(cyanSoft.opacity(0.60)), style: StrokeStyle(lineWidth: S*0.006, lineCap:.round))
                }
            }
        default: break
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  LISTENING RING
    // ─────────────────────────────────────────────────────────────────────────
    static func drawListenRing(_ ctx: inout GraphicsContext, cx: CGFloat, cy: CGFloat, R: CGFloat, t: Double) {
        let pulse = CGFloat((sin(t*3.0)+1)/2)
        let rr    = R * 1.08 + R * 0.10 * pulse
        var ring = Path()
        ring.addArc(center: CGPoint(x:cx, y:cy), radius: rr,
                    startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: R*0.015))
            l.stroke(ring, with: .color(cyan.opacity(0.55 - 0.35*Double(pulse))), style: StrokeStyle(lineWidth: R*0.028))
        }
        ctx.stroke(ring, with: .color(cyan.opacity(0.38 - 0.22*Double(pulse))), style: StrokeStyle(lineWidth: R*0.018))
    }
}

// MARK: - Keyword → Expression

enum RobotFaceMood {
    static func guess(from text: String) -> RobotFaceExpression? {
        let lower = text.lowercased()
        func has(_ phrases: [String]) -> Bool { phrases.contains { lower.contains($0) } }
        if has(["buồn ngủ","ngáp"])                           { return .sleepy }
        if has(["haha","hihi","hehe","ha ha","hì hì"])        { return .happy }
        if has(["thật sao","trời ơi","bất ngờ","wow","ôi"])  { return .surprised }
        if has(["hmm","ừm","để mình nghĩ","để xem"])         { return .thinking }
        if has(["xin lỗi","rất tiếc","tiếc quá","buồn"])     { return .sad }
        if has(["ngại","ngượng","xấu hổ"])                   { return .confused }
        if has(["tức","bực","tệ","sai rồi"])                 { return .angry }
        if has(["tuyệt","vui","thích","chúc mừng","cảm ơn"]) { return .happy }
        return nil
    }
}

// MARK: - Preview / Gallery screen

struct RobotFacePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var expression: RobotFaceExpression = .idle
    @State private var simulateSpeech = false
    @State private var showListening  = false
    @State private var autoPlay = false
    @State private var autoTask: Task<Void,Never>?
    @State private var pokeTask: Task<Void,Never>?

    private static func fakeSpeech(_ d: Date) -> CGFloat {
        let t = d.timeIntervalSinceReferenceDate
        return CGFloat(abs(sin(t*9.0)) * (0.5 + 0.5*abs(sin(t*2.3))))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    RobotFaceView(
                        expression: expression,
                        speakingLevel: { simulateSpeech ? RobotFacePreviewView.fakeSpeech($0) : 0 },
                        isListening: showListening,
                        onTap: { poke() }
                    )
                    .frame(height: 260)
                    .background(Color(red:0.04,green:0.05,blue:0.13).cornerRadius(20))

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                        ForEach(RobotFaceExpression.allCases) { item in
                            Button {
                                autoTask?.cancel(); autoPlay = false
                                expression = item
                            } label: {
                                Text(item.title)
                                    .font(.footnote)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(expression == item ? Color.accentColor : Color(.secondarySystemBackground))
                                    .foregroundColor(expression == item ? .white : .primary)
                                    .cornerRadius(10)
                            }
                        }
                    }

                    Toggle("Giả lập đang nói (khớp miệng)", isOn: $simulateSpeech)
                    Toggle("Vòng sáng đang nghe",           isOn: $showListening)

                    Button(autoPlay ? "Dừng chạy thử" : "Chạy thử lần lượt") {
                        toggleAutoPlay()
                    }
                    .font(.footnote)

                    Text("Chạm vào mặt robot để trêu thử.\nKiểu biểu cảm ở đây cũng áp dụng cho màn hình gọi thoại.")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding()
            }
            .navigationTitle("Biểu cảm robot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { autoTask?.cancel(); pokeTask?.cancel(); dismiss() }
                }
            }
            .onDisappear { autoTask?.cancel(); pokeTask?.cancel() }
        }
    }

    private func toggleAutoPlay() {
        if autoPlay { autoTask?.cancel(); autoPlay = false; return }
        autoPlay = true
        autoTask = Task {
            while !Task.isCancelled {
                for item in RobotFaceExpression.allCases {
                    guard !Task.isCancelled else { return }
                    expression = item
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                }
            }
        }
    }

    private func poke() {
        pokeTask?.cancel()
        let before = expression
        pokeTask = Task {
            expression = .surprised
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            expression = .happy
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            expression = before
        }
    }
}
