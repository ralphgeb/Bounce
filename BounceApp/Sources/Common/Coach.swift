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
        case drag, launch, swap
    }

    enum Gesture { case none, swipeLeft, swipeRight, swipeAny, tap, hold, dragSideways, swapRight }

    /// Little drawings for the steps that explain a rule.
    enum Picture { case none, switchFour, switchFive, switchT, hideLight, hueFixed, mazeGlow }

    struct Step {
        var text: String
        var waitFor: Action
        var gesture: Gesture = .none
        var picture: Picture = .none
    }

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

    /// Settings › Show tutorials again.
    static func resetAll() {
        for g in ["bounce", "hide", "maze", "switch", "hue"] {
            UserDefaults.standard.removeObject(forKey: "tutorial.\(g)")
        }
    }
}

/// Draws the current tutorial step over a game: the line, a finger showing the gesture, a small
/// picture when there is one, the step dots, and Skip.
struct CoachOverlay: View {
    let coach: Coach
    let colors: Colors

    var body: some View {
        if let step = coach.current {
            ZStack {
                // Tap-to-continue steps dim the game a little and take the tap anywhere.
                if step.waitFor == .tapToContinue {
                    colors.background.opacity(0.82)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { coach.next() }
                }

                VStack(spacing: 22) {
                    Spacer()
                    if step.picture != .none {
                        CoachPicture(picture: step.picture, colors: colors)
                            .frame(width: 220, height: 90)
                            .allowsHitTesting(false)
                    }
                    if step.gesture != .none {
                        FingerHint(gesture: step.gesture, colors: colors)
                            .frame(width: 160, height: 70)
                            .allowsHitTesting(false)
                    }
                    Text(step.text)
                        .font(.system(size: 16, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(colors.ink)
                        .frame(maxWidth: 280)
                        .allowsHitTesting(false)
                    if step.waitFor == .tapToContinue {
                        Text("Tap to continue")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(2)
                            .textCase(.uppercase)
                            .foregroundStyle(colors.ink.opacity(0.4))
                            .allowsHitTesting(false)
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<coach.steps.count, id: \.self) { i in
                            Rectangle()
                                .fill(i == coach.index ? colors.accent : colors.ink.opacity(0.18))
                                .frame(width: i == coach.index ? 14 : 6, height: 6)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: coach.index)
                    .allowsHitTesting(false)
                    Button("Skip") { coach.finish() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(colors.ink.opacity(0.45))
                        .padding(.bottom, 30)
                }
                .id(coach.stepID)
                .transition(.opacity.combined(with: .offset(y: 10)))
            }
            .animation(.easeOut(duration: 0.25), value: coach.stepID)
        }
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
                let s: CGFloat = 22, g: CGFloat = 4
                func sq(_ x: CGFloat, _ y: CGFloat, _ c: Color) {
                    ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(c))
                }
                let shade = colors.ink.opacity(0.4)
                let y = size.height / 2 - s / 2
                switch picture {
                case .switchFour, .switchFive:
                    let n = picture == .switchFour ? 4 : 5
                    let w = CGFloat(n) * (s + g)
                    for i in 0..<n { sq(CGFloat(i) * (s + g), y, shade) }
                    arrow(&ctx, from: w + 6, to: w + 34, y: size.height / 2)
                    let r = CGRect(x: w + 44, y: y, width: s, height: s)
                    if picture == .switchFour {
                        ctx.fill(Chamfer.path(in: r), with: .color(shade))
                        ctx.fill(Path(CGRect(x: r.midX - 5, y: r.midY - 1, width: 10, height: 2)), with: .color(colors.background))
                    } else {
                        ctx.fill(Path(ellipseIn: r), with: .color(shade))
                        ctx.fill(Path(ellipseIn: CGRect(x: r.midX - 2.5, y: r.midY - 2.5, width: 5, height: 5)), with: .color(colors.background))
                    }
                case .switchT:
                    // A T of five squares, then the diamond.
                    let ox: CGFloat = 0, oy = size.height / 2 - s * 1.5 - g
                    for i in 0..<3 { sq(ox + CGFloat(i) * (s + g), oy, shade) }
                    for j in 1..<3 { sq(ox + (s + g), oy + CGFloat(j) * (s + g), shade) }
                    let w = 3 * (s + g)
                    arrow(&ctx, from: w + 6, to: w + 34, y: size.height / 2)
                    let r = CGRect(x: w + 44, y: size.height / 2 - s / 2, width: s, height: s)
                    var p = Path()
                    p.move(to: CGPoint(x: r.midX, y: r.minY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
                    p.addLine(to: CGPoint(x: r.midX, y: r.maxY)); p.addLine(to: CGPoint(x: r.minX, y: r.midY)); p.closeSubpath()
                    ctx.fill(p, with: .color(shade))
                case .hideLight, .mazeGlow:
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - 60, y: c.y - 60, width: 120, height: 120)),
                             with: .radialGradient(Gradient(colors: [colors.ink.opacity(0.35), colors.ink.opacity(0)]), center: c, startRadius: 0, endRadius: 60))
                    if picture == .hideLight {
                        for i in 0..<5 {
                            let a = Double(i) / 5 * 2 * .pi + t * 0.3
                            let p = CGPoint(x: c.x + cos(a) * 38 - 8, y: c.y + sin(a) * 26 - 8)
                            ctx.fill(Path(CGRect(x: p.x, y: p.y, width: 16, height: 16)), with: .color(colors.ink.opacity(0.7)))
                        }
                    }
                    let r: CGFloat = picture == .mazeGlow ? 5 : 6
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(colors.accent))
                case .hueFixed:
                    for i in 0..<6 {
                        let k = Double(i) / 5
                        let x = CGFloat(i) * (s + g) + 30
                        sq(x, y, colors.accent.opacity(0.2 + 0.8 * k))
                        if i == 0 || i == 5 {
                            ctx.fill(Path(ellipseIn: CGRect(x: x + s / 2 - 2.5, y: y + s / 2 - 2.5, width: 5, height: 5)), with: .color(colors.ink))
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
