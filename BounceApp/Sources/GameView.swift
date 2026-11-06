import SwiftUI

/// The playing screen: the board on a canvas, the score and lives on top.
struct GameView: View {
    let game: Game
    let colors: Colors
    let safeTop: CGFloat
    let safeBottom: CGFloat

    @State private var touching = false

    var body: some View {
        let frame = game.frame
        ZStack {
            Canvas { ctx, _ in
                _ = frame
                draw(&ctx)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { v in
                        if !touching {
                            touching = true
                            game.launch()
                        }
                        game.targetX = v.location.x
                    }
                    .onEnded { _ in touching = false }
            )

            VStack(spacing: 0) {
                hud
                Spacer()
                Text(formatTime(game.elapsed).uppercased())
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .tracking(1.1)
                    .foregroundStyle(colors.ink.opacity(0.35))
                    .padding(.bottom, 6)
            }
            .allowsHitTesting(game.phase == .playing)

            if let t = game.toast {
                Text(t.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(4)
                    .foregroundStyle(colors.accent)
                    .id(game.toastID)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .allowsHitTesting(false)
            }

            if game.phase == .paused { paused }
        }
        .animation(.easeOut(duration: 0.25), value: game.toastID)
        .animation(.easeOut(duration: 0.2), value: game.toast == nil)
    }

    // MARK: Score, chain, best

    private var hud: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Score").bounceLabel(colors)
                Text("\(game.score)")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(colors.ink)
                    .contentTransition(.numericText())
                HStack(spacing: 4) {
                    ForEach(0..<game.lives, id: \.self) { i in
                        Rectangle()
                            .fill(game.freshLife && i == game.lives - 1 ? colors.accent : colors.ink)
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 6)
                .accessibilityElement()
                .accessibilityLabel("\(game.lives) lives")
            }
            Spacer()
            VStack(spacing: 8) {
                Button {
                    game.pause()
                    Haptics.tap(.light)
                } label: {
                    HStack(spacing: 4) {
                        Rectangle().frame(width: 3, height: 12)
                        Rectangle().frame(width: 3, height: 12)
                    }
                    .foregroundStyle(colors.ink.opacity(0.5))
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Pause")
                Text(game.chain > 1 ? "×\(game.chain)" : " ")
                    .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(colors.accent)
                    .scaleEffect(game.chain > 1 ? 1 : 0.6)
                    .animation(.spring(response: 0.25, dampingFraction: 0.5), value: game.chain)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Best").bounceLabel(colors)
                Text("\(Settings.shared.best)")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(colors.ink.opacity(0.35))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var paused: some View {
        ZStack {
            colors.background.opacity(0.88).ignoresSafeArea()
            VStack(spacing: 26) {
                Text("Paused")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(4)
                    .textCase(.uppercase)
                    .foregroundStyle(colors.ink.opacity(0.55))
                OutlineButton(title: "Carry on", colors: colors) { game.resume() }
                Button("End game") { game.home() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.ink.opacity(0.5))
            }
        }
        .transition(.opacity)
    }

    // MARK: Drawing

    private func draw(_ ctx: inout GraphicsContext) {
        let ink = colors.ink, accent = colors.accent
        let w = game.size.width

        // Line above the paddle: warms to the accent as the wall gets close.
        let low = game.blocks.reduce(0) { max($0, $1.rect.maxY) }
        let near = max(0, min(1, (low - (game.paddleY - 220)) / 200))
        ctx.fill(Path(CGRect(x: game.side, y: game.dangerY, width: w - game.side * 2, height: 1)),
                 with: .color((near > 0.05 ? accent : ink).opacity(0.08 + near * 0.5)))

        if game.flash > 0 {
            ctx.fill(Path(CGRect(origin: .zero, size: game.size)), with: .color(accent.opacity(game.flash * 0.12)))
        }

        // Blocks: plain squares, darker the tougher they are. The same gap across and down.
        for b in game.blocks {
            let path = Path(b.rect)
            let r = b.rect
            let o = b.age
            switch b.kind {
            case .plain:
                let alpha = b.hp >= 3 ? 1 : b.hp == 2 ? 0.6 : 0.2
                ctx.fill(path, with: .color(ink.opacity(alpha * o)))
            case .split:
                ctx.fill(path, with: .color(accent.opacity(o)))
            case .blaster:
                // An accent outline and a big inner square: the gap is as wide as the outline.
                let line: CGFloat = 2.5
                ctx.stroke(Path(r.insetBy(dx: line / 2, dy: line / 2)), with: .color(accent.opacity(o)), lineWidth: line)
                ctx.fill(Path(r.insetBy(dx: line * 2, dy: line * 2)), with: .color(accent.opacity(o)))
            case .row, .column:
                // Chamfered square with a short line in the middle: across for a row, down for a column.
                ctx.fill(Chamfer.path(in: r), with: .color(ink.opacity(o)))
                let len = r.width * 0.44, t: CGFloat = 2.5
                let mark = b.kind == .row
                    ? CGRect(x: r.midX - len / 2, y: r.midY - t / 2, width: len, height: t)
                    : CGRect(x: r.midX - t / 2, y: r.midY - len / 2, width: t, height: len)
                ctx.fill(Path(mark), with: .color(colors.background.opacity(o)))
            case .bomb:
                // A big circle, as wide as a square: clears the screen.
                ctx.fill(Path(ellipseIn: r), with: .color(ink.opacity(o)))
                ctx.fill(Path(ellipseIn: r.insetBy(dx: r.width * 0.36, dy: r.width * 0.36)), with: .color(accent.opacity(o)))
            }
            if b.hit > 0 { ctx.fill(path, with: .color(accent.opacity(b.hit * 0.7))) }
        }

        for sweep in game.sweeps {
            ctx.fill(Path(sweep.rect), with: .color(accent.opacity(sweep.life * 0.35)))
        }

        // Shots from the paddle.
        for s in game.bullets {
            ctx.fill(Path(CGRect(x: s.x - 1.5, y: s.y - 10, width: 3, height: 10)), with: .color(accent))
        }

        for p in game.particles {
            ctx.fill(Path(CGRect(x: p.p.x, y: p.p.y, width: p.size, height: p.size)), with: .color(ink.opacity(p.life * 0.7)))
        }

        // Paddle
        let pr = CGRect(x: game.paddleX - game.paddleW / 2, y: game.paddleY - game.paddleH / 2, width: game.paddleW, height: game.paddleH)
        ctx.fill(Path(roundedRect: pr, cornerRadius: game.paddleH / 2), with: .color(ink))
        if game.shootLeft > 0 {
            // The two cannons in the accent, and the time left as a thin line under the paddle.
            for x in [pr.minX + 1, pr.maxX - 7] {
                ctx.fill(Path(CGRect(x: x, y: pr.minY - 4, width: 6, height: 4)), with: .color(accent))
            }
            let f = game.shootLeft / game.shootTime
            ctx.fill(Path(CGRect(x: pr.minX, y: pr.maxY + 6, width: pr.width * f, height: 2)), with: .color(accent.opacity(0.7)))
        }

        // Balls: the accent dot, with a short fading trail.
        for ball in game.balls {
            let n = Double(ball.trail.count)
            for (i, t) in ball.trail.enumerated() {
                let r = ball.r * (0.5 + CGFloat(i) / 16)
                ctx.fill(Path(ellipseIn: CGRect(x: t.x - r, y: t.y - r, width: r * 2, height: r * 2)),
                         with: .color(accent.opacity((Double(i) + 1) / n * 0.18)))
            }
            let r = ball.r
            ctx.fill(Path(ellipseIn: CGRect(x: ball.p.x - r, y: ball.p.y - r, width: r * 2, height: r * 2)), with: .color(accent))
        }
    }
}

/// A square with small cut corners: the row and column clearers.
enum Chamfer {
    static func path(in r: CGRect, cut: CGFloat? = nil) -> Path {
        let c = cut ?? r.width * 0.16
        var p = Path()
        p.move(to: CGPoint(x: r.minX + c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + c))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.maxX - c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + c, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - c))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + c))
        p.closeSubpath()
        return p
    }
}

struct ChamferShape: Shape {
    func path(in rect: CGRect) -> Path { Chamfer.path(in: rect) }
}

/// The one button style: a thin outline with square corners, spaced capitals.
struct OutlineButton: View {
    let title: String
    let colors: Colors
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tap(.medium)
            action()
        } label: {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(3.6)
                .foregroundStyle(colors.ink)
                .frame(width: 150, height: 44)
                .overlay(Rectangle().strokeBorder(colors.ink, lineWidth: 1.5))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(colors: colors))
    }
}

private struct PressStyle: ButtonStyle {
    let colors: Colors
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? colors.ink.opacity(0.08) : .clear)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
