import SwiftUI

/// A first-time tutorial, built the way the best quick ones work: learn by doing, one thing at a
/// time, and only move on once you've done it. Steps that need an action wait for the game to report
/// it; the others (a picture and a line) move on with a tap. Skip is always there.
@MainActor
@Observable
final class Coach {
    enum Action: Equatable {
        case tapToContinue
        case swipeLeft, swipeRight, swipeAny
        case tap, dropDot, pickDot, hold
        case drag, launch, swap, goal
    }

    enum Gesture { case none, swipeLeft, swipeRight, swipeAny, tap, hold, pinch, dragSideways, swapRight }

    /// Little drawings for the steps that explain a rule.
    enum Picture { case none, wallDown, bouncePowers, hueFixed, mazeGlow }

    /// Where an action step's panel sits: near the top (under the score), or low (near the thumb).
    enum Place { case top, low }

    struct Step {
        var text: String
        var waitFor: Action
        var gesture: Gesture = .none
        var picture: Picture = .none
        var place: Place = .top
        /// A tap-to-continue step shown as the small panel above the board instead of a card over
        /// it, so the board stays fully visible (Hue's tutorial).
        var inline = false
        /// Something on the game's own screen this step is about (the game highlights it).
        var pointer: Pointer? = nil
    }

    enum Pointer { case counter }

    private(set) var steps: [Step] = []
    private(set) var index = 0
    private(set) var active = false
    private(set) var stepID = 0
    @ObservationIgnored private var key = ""
    @ObservationIgnored private var onFinish: (() -> Void)?

    var current: Step? { active && index < steps.count ? steps[index] : nil }

    /// Starts the tutorial for this game if it has never been seen (or Settings asked to show it again).
    func begin(_ game: String, steps: [Step], onFinish: (() -> Void)? = nil) {
        key = "tutorial.\(game)"
        guard !UserDefaults.standard.bool(forKey: key) else { active = false; return }
        self.steps = steps
        self.onFinish = onFinish
        index = 0
        stepID += 1
        active = true
    }

    /// The game reports what the player just did; matching steps move on.
    func did(_ action: Action) {
        guard let s = current else { return }
        let ok = s.waitFor == action || (s.waitFor == .swipeAny && (action == .swipeLeft || action == .swipeRight))
        guard ok else { return }
        next()
    }

    func next() {
        Haptics.tap(.light, intensity: 0.6)
        Sound.shared.play("tick", volume: 0.8)
        if index + 1 < steps.count {
            index += 1
            stepID += 1
        } else {
            finish()
        }
    }

    func finish() {
        active = false
        UserDefaults.standard.set(true, forKey: key)
        onFinish?()
        onFinish = nil
    }

    /// Has this game's tutorial been seen (or skipped)?
    static func seen(_ game: String) -> Bool { UserDefaults.standard.bool(forKey: "tutorial.\(game)") }

    /// Settings › Show tutorials again.
    static func resetAll() {
        for g in ["bounce", "maze", "switch", "hue"] {
            UserDefaults.standard.removeObject(forKey: "tutorial.\(g)")
        }
    }
}

/// Draws the current tutorial step over a game.
/// Rule cards fill the middle of the screen: a picture, the line, "Tap to continue".
/// Action steps leave the game playable: a small centred panel at the top (or low), the finger
/// acting out the gesture, and the step dots. Skip is always there.
struct CoachOverlay: View {
    let coach: Coach
    let colors: Colors

    var body: some View {
        if let step = coach.current {
            ZStack {
                if step.waitFor == .tapToContinue && !step.inline {
                    card(step)
                } else {
                    if step.waitFor == .tapToContinue {
                        // Tap anywhere to continue; the board stays in full view.
                        Color.clear
                            .contentShape(Rectangle())
                            .ignoresSafeArea()
                            .onTapGesture { coach.next() }
                    }
                    panel(step)
                }
            }
            .id(coach.stepID)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.25), value: coach.stepID)
        }
    }

    // MARK: Rule card

    private func card(_ step: Coach.Step) -> some View {
        ZStack {
            colors.background.opacity(0.78)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { coach.next() }
            VStack(spacing: 26) {
                Spacer()
                if step.picture != .none {
                    CoachPicture(picture: step.picture, colors: colors)
                        .frame(width: 240, height: 120)
                }
                line(step.text, size: 17)
                Text("Tap to continue")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2.4)
                    .textCase(.uppercase)
                    .foregroundStyle(colors.ink.opacity(0.4))
                Spacer()
                dots.padding(.bottom, 70)
            }
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            VStack { Spacer(); skip.padding(.bottom, 24) }
        }
    }

    // MARK: Action panel

    private func panel(_ step: Coach.Step) -> some View {
        ZStack {
            VStack(spacing: 0) {
                if step.place == .low { Spacer() }
                VStack(spacing: 14) {
                    line(step.text, size: 16)
                    if step.waitFor == .tapToContinue {
                        Text("Tap to continue")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(2.4)
                            .textCase(.uppercase)
                            .foregroundStyle(colors.ink.opacity(0.45))
                    }
                    if step.gesture != .none {
                        FingerHint(gesture: step.gesture, colors: colors)
                            .frame(width: 170, height: 60)
                    }
                    dots
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 22)
                .frame(maxWidth: 320)
                // Barely there, so the game shows through.
                .background(colors.background.opacity(0.35))
                .allowsHitTesting(false)
                if step.place == .top { Spacer() }
            }
            .padding(.top, step.place == .top ? 104 : 0)
            .padding(.bottom, step.place == .low ? 190 : 0)

            // Skip always sits at the bottom of the screen.
            VStack { Spacer(); skip.padding(.bottom, 24) }
        }
    }

    // MARK: Parts

    private func line(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .font(.system(size: size, weight: .semibold))
            .shadow(color: colors.background.opacity(0.9), radius: 6)
            .lineSpacing(4)
            .multilineTextAlignment(.center)
            .foregroundStyle(colors.ink)
            .frame(maxWidth: 290)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<coach.steps.count, id: \.self) { i in
                Rectangle()
                    .fill(i == coach.index ? colors.accent : colors.ink.opacity(0.18))
                    .frame(width: i == coach.index ? 14 : 6, height: 6)
            }
        }
    }

    private var skip: some View {
        Button("Skip tutorial") { coach.finish() }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(colors.ink.opacity(0.45))
            .frame(height: 36)
    }
}

/// A finger (a soft ring) acting out the gesture, over and over.
private struct FingerHint: View {
    let gesture: Coach.Gesture
    let colors: Colors

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                let mid = CGPoint(x: size.width / 2, y: size.height / 2)
                var p = mid
                var press = 0.0
                var alpha = 1.0
                let ease: (Double) -> Double = { x in x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2 }
                switch gesture {
                case .swipeLeft, .swipeRight, .swipeAny, .dragSideways, .swapRight:
                    let dir: CGFloat = gesture == .swipeLeft ? -1 : 1
                    let reach = size.width * (gesture == .dragSideways ? 0.4 : 0.32)
                    let k = min(1, max(0, (t - 0.15) / 0.55))
                    let start = gesture == .dragSideways ? mid.x - reach : mid.x - dir * reach * 0.5
                    let span = gesture == .dragSideways ? reach * 2 : dir * reach
                    p.x = start + span * CGFloat(gesture == .dragSideways ? (sin(t * 2 * .pi) + 1) / 2 : ease(k))
                    press = gesture == .dragSideways ? 1 : (t > 0.1 && t < 0.75 ? 1 : 0)
                    alpha = gesture == .dragSideways ? 1 : (t < 0.85 ? 1 : (1 - t) / 0.15)
                    if gesture != .dragSideways && press > 0 {
                        // A short trail behind the finger.
                        var trail = Path()
                        trail.move(to: CGPoint(x: mid.x - dir * reach * 0.5, y: mid.y))
                        trail.addLine(to: p)
                        ctx.stroke(trail, with: .color(colors.accent.opacity(0.35)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                case .pinch:
                    // Two fingers moving together, then apart again.
                    let k = t < 0.55 ? (1 - cos(t / 0.55 * .pi)) / 2 : max(0, 1 - (t - 0.55) / 0.45)
                    let spread = 46 - 30 * CGFloat(k)
                    for side in [-1.0, 1.0] {
                        let q = CGPoint(x: mid.x + CGFloat(side) * spread * 0.8, y: mid.y - CGFloat(side) * spread * 0.4)
                        ctx.fill(Path(ellipseIn: CGRect(x: q.x - 13, y: q.y - 13, width: 26, height: 26)), with: .color(colors.ink.opacity(0.2)))
                        ctx.stroke(Path(ellipseIn: CGRect(x: q.x - 13, y: q.y - 13, width: 26, height: 26)), with: .color(colors.ink.opacity(0.55)), lineWidth: 1.5)
                    }
                    return
                case .tap:
                    press = t < 0.25 ? 1 : 0
                    alpha = 1
                case .hold:
                    press = t < 0.8 ? 1 : 0
                    if press > 0 {
                        let r = 18 + 14 * min(1, t / 0.8)
                        ctx.stroke(Path(ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: r * 2, height: r * 2)),
                                   with: .color(colors.accent.opacity(0.6 * (1 - t / 0.8))), lineWidth: 2)
                    }
                case .none:
                    return
                }
                let r: CGFloat = press > 0 ? 13 : 16
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                         with: .color(colors.ink.opacity((press > 0 ? 0.22 : 0.1) * alpha)))
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                           with: .color(colors.ink.opacity(0.55 * alpha)), lineWidth: 1.5)
            }
        }
    }
}

/// The pictures for rule steps, drawn in the game's own shapes.
private struct CoachPicture: View {
    let picture: Coach.Picture
    let colors: Colors

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                switch picture {
                case .wallDown:
                    // Rows of squares drifting down towards the line over the paddle.
                    let cols = 7, cell: CGFloat = 20, gap: CGFloat = 4
                    let w = CGFloat(cols) * (cell + gap) - gap
                    let ox = (size.width - w) / 2
                    let lineY = size.height - 26
                    let drift = CGFloat((t * 14).truncatingRemainder(dividingBy: Double(cell + gap)))
                    for r in 0..<3 {
                        let ry = CGFloat(r) * (cell + gap) + drift - 6
                        let fade = min(1, max(0, Double(ry + 10) / 20))
                        for c in 0..<cols where (r * 3 + c * 5) % 7 != 0 {
                            let shade = [0.9, 0.5, 0.2][(r + c) % 3]
                            ctx.fill(Path(CGRect(x: ox + CGFloat(c) * (cell + gap), y: ry, width: cell, height: cell)),
                                     with: .color(colors.ink.opacity(shade * fade)))
                        }
                    }
                    ctx.fill(Path(CGRect(x: ox, y: lineY, width: w, height: 1.5)), with: .color(colors.accent))
                    ctx.fill(Path(roundedRect: CGRect(x: size.width / 2 - 26, y: lineY + 12, width: 52, height: 7), cornerRadius: 3.5),
                             with: .color(colors.ink))
                    for x in [ox - 16, ox + w + 16] {
                        var p = Path()
                        p.move(to: CGPoint(x: x, y: 20)); p.addLine(to: CGPoint(x: x, y: lineY - 14))
                        p.move(to: CGPoint(x: x - 5, y: lineY - 20)); p.addLine(to: CGPoint(x: x, y: lineY - 14)); p.addLine(to: CGPoint(x: x + 5, y: lineY - 20))
                        ctx.stroke(p, with: .color(colors.ink.opacity(0.3)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    }
                case .bouncePowers:
                    // The six power-ups, in a row.
                    let n = 6, cell: CGFloat = 24, gap: CGFloat = 12
                    let w = CGFloat(n) * cell + CGFloat(n - 1) * gap
                    let ox = (size.width - w) / 2, oy = size.height / 2 - cell / 2
                    for i in 0..<n {
                        let r = CGRect(x: ox + CGFloat(i) * (cell + gap), y: oy, width: cell, height: cell)
                        switch i {
                        case 0:
                            ctx.fill(Path(r), with: .color(colors.accent))
                        case 1, 2:
                            ctx.fill(Chamfer.path(in: r), with: .color(colors.accent))
                            let m = i == 1 ? CGRect(x: r.midX - 6, y: r.midY - 1.25, width: 12, height: 2.5)
                                           : CGRect(x: r.midX - 1.25, y: r.midY - 6, width: 2.5, height: 12)
                            ctx.fill(Path(m), with: .color(colors.background))
                        case 3:
                            ctx.stroke(Path(r.insetBy(dx: 1, dy: 1)), with: .color(colors.accent), lineWidth: 2)
                            ctx.fill(Path(r.insetBy(dx: 4, dy: 4)), with: .color(colors.accent))
                        case 5:
                            ctx.fill(Heart.path(in: r), with: .color(colors.accent))
                        default:
                            ctx.fill(Path(ellipseIn: r), with: .color(colors.accent))
                        }
                    }
                case .mazeGlow:
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let pulse = 1 + 0.1 * sin(t * 3)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 54, y: c.y - 54, width: 108, height: 108)),
                             with: .radialGradient(Gradient(colors: [colors.accent.opacity(0.5), colors.accent.opacity(0)]), center: c, startRadius: 0, endRadius: 54))
                    ctx.fill(Star.path(center: c, radius: 14 * pulse, turn: t * 0.4), with: .color(colors.accent))
                case .hueFixed:
                    let n = 7, cell: CGFloat = 24, gap: CGFloat = 4
                    let w = CGFloat(n) * (cell + gap) - gap
                    let ox = (size.width - w) / 2, oy = size.height / 2 - cell / 2
                    for i in 0..<n {
                        let k = Double(i) / Double(n - 1)
                        let x = ox + CGFloat(i) * (cell + gap)
                        ctx.fill(Path(CGRect(x: x, y: oy, width: cell, height: cell)),
                                 with: .color(HueColor.shade(colors.accent, -0.6 + 1.2 * k)))
                        if i == 0 || i == n - 1 {
                            ctx.fill(Path(ellipseIn: CGRect(x: x + cell / 2 - 2.5, y: oy + cell / 2 - 2.5, width: 5, height: 5)),
                                     with: .color(i == 0 ? Color.white.opacity(0.8) : Color.black.opacity(0.55)))
                        }
                    }
                case .none:
                    break
                }
            }
        }
    }

    private func arrow(_ ctx: inout GraphicsContext, from a: CGFloat, to b: CGFloat, y: CGFloat) {
        var p = Path()
        p.move(to: CGPoint(x: a, y: y)); p.addLine(to: CGPoint(x: b, y: y))
        p.move(to: CGPoint(x: b - 6, y: y - 5)); p.addLine(to: CGPoint(x: b, y: y)); p.addLine(to: CGPoint(x: b - 6, y: y + 5))
        ctx.stroke(p, with: .color(colors.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
}

/// The way out of a maze: a four-pointed star.
enum Star {
    static func path(center c: CGPoint, radius r: CGFloat, turn: Double = 0) -> Path {
        var p = Path()
        for i in 0..<8 {
            let a = Double(i) / 8 * 2 * .pi + turn - .pi / 2
            let rr = i % 2 == 0 ? r : r * 0.38
            let q = CGPoint(x: c.x + CGFloat(cos(a)) * rr, y: c.y + CGFloat(sin(a)) * rr)
            if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
        }
        p.closeSubpath()
        return p
    }
}

struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        Star.path(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2)
    }
}
