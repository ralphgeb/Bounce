import SwiftUI

/// Switch's colours: five that go together, built around the theme's accent (Colour), and the logo.
enum SwitchColors {
    /// The six colours, ordered so index 5 is the accent itself.
    ///
    /// Mono: three greys of the main colour (90%, 55%, 20%) and three tones of the accent
    /// (deep, light, the accent).
    /// Colour: two tones of a partner colour (the accent of another look, picked to sit well with
    /// yours), a dark grey, and three tones of the accent.
    @MainActor static func palette(_ p: SwitchGame.Palette, _ colors: Colors) -> [Color] {
        let a = colors.accent
        let accentTones = [HueColor.shade(a, -0.38), HueColor.shade(a, 0.5), a]
        switch p {
        case .mono:
            return [colors.ink.opacity(0.9), colors.ink.opacity(0.55), colors.ink.opacity(0.2)] + accentTones
        case .colour:
            let b = Settings.shared.secondAccent.color
            return [HueColor.shade(b, -0.3), HueColor.shade(b, 0.45), colors.ink.opacity(0.85)] + accentTones
        }
    }

    static func logo(_ colors: Colors) -> [Color] {
        [colors.ink.opacity(0.65), colors.ink.opacity(0.9), colors.ink.opacity(0.15), colors.accent, colors.ink.opacity(0.4), colors.ink.opacity(0.9)]
    }
}

/// Where the board sits on screen.
struct SwitchLayout {
    let origin: CGPoint
    let cell: CGFloat

    init(size: CGSize, cols: Int, rows: Int) {
        let side: CGFloat = 18
        let byWidth = (size.width - side * 2) / CGFloat(cols)
        let byHeight = (size.height - 330) / CGFloat(rows)
        cell = max(20, min(byWidth, byHeight))
        let w = cell * CGFloat(cols), h = cell * CGFloat(rows)
        origin = CGPoint(x: (size.width - w) / 2, y: max(150, (size.height - h) / 2 + 30))
    }

    func cellAt(_ p: CGPoint, cols: Int, rows: Int) -> Int? {
        let x = Int(floor((p.x - origin.x) / cell)), y = Int(floor((p.y - origin.y) / cell))
        guard x >= 0, y >= 0, x < cols, y < rows else { return nil }
        return y * cols + x
    }
}

/// Playing Switch: the board, the score and best, and a hint button.
struct SwitchView: View {
    let game: SwitchGame
    let colors: Colors

    @State private var swiped = false
    @State private var from: Int?
    /// The six colours, worked out once (not every frame).
    @State private var palette: [Color] = []

    var body: some View {
        let frame = game.frame
        GeometryReader { geo in
            let layout = SwitchLayout(size: geo.size, cols: game.cols, rows: game.rows)
            ZStack {
                Canvas { ctx, _ in
                    _ = frame
                    draw(&ctx, layout)
                }
                .onAppear { palette = SwitchColors.palette(game.palette, colors) }
                .onChange(of: game.palette) { palette = SwitchColors.palette(game.palette, colors) }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if from == nil {
                                from = layout.cellAt(v.startLocation, cols: game.cols, rows: game.rows)
                                game.pressed = from
                            }
                            guard !swiped, let cell = from else { return }
                            let t = v.translation
                            guard hypot(t.width, t.height) > layout.cell * 0.3 else { return }
                            swiped = true
                            game.pressed = nil
                            if abs(t.width) > abs(t.height) {
                                game.swipe(from: cell, dx: t.width > 0 ? 1 : -1, dy: 0)
                            } else {
                                game.swipe(from: cell, dx: 0, dy: t.height > 0 ? 1 : -1)
                            }
                        }
                        .onEnded { _ in
                            swiped = false
                            from = nil
                            game.pressed = nil
                        }
                )

                VStack(spacing: 0) {
                    hud
                    Spacer()
                    // One move that works, when you're stuck.
                    if game.tutorial == nil { Button {
                        game.showHint()
                    } label: {
                        Text("Hint")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(3)
                            .textCase(.uppercase)
                            .foregroundStyle(colors.ink.opacity(0.55))
                            .frame(width: 110, height: 40)
                            .overlay(Rectangle().strokeBorder(colors.ink.opacity(0.25), lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .padding(.bottom, 36) }
                }

                if let t = game.toast {
                    Text(t.uppercased())
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .tracking(3)
                        .foregroundStyle(colors.accent)
                        .position(x: geo.size.width / 2, y: layout.origin.y - 22)
                        .id(game.toastID)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        .allowsHitTesting(false)
                }

                // The tutorial steps aside while paused; Carry on sits on top.
                if game.phase != .paused { CoachOverlay(coach: game.coach, colors: colors) }
                if game.phase == .paused { paused }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: game.toastID)
    }

    private var hud: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Score").bounceLabel(colors)
                Text("\(game.score)")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(colors.ink)
                    .contentTransition(.numericText())
            }
            Spacer()
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
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Best").bounceLabel(colors)
                Text("\(Settings.shared.switchBest)")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(colors.ink.opacity(0.35))
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var paused: some View {
        ZStack {
            colors.background.opacity(0.9).ignoresSafeArea()
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

    private func draw(_ ctx: inout GraphicsContext, _ L: SwitchLayout) {
        let C = L.cell
        let gap = C * 0.1
        let w = C * CGFloat(game.cols), h = C * CGFloat(game.rows)

        // The board's faint grid of empty places.
        var places = Path()
        for y in 0..<game.rows {
            for x in 0..<game.cols {
                places.addRect(CGRect(x: L.origin.x + CGFloat(x) * C + gap / 2, y: L.origin.y + CGFloat(y) * C + gap / 2, width: C - gap, height: C - gap))
            }
        }
        ctx.fill(places, with: .color(colors.ink.opacity(0.035)))

        // Rows and columns just cleared, and circles just gone off.
        for s in game.sweeps {
            let r = s.across
                ? CGRect(x: L.origin.x - 6, y: L.origin.y + CGFloat(s.index) * C, width: w + 12, height: C)
                : CGRect(x: L.origin.x + CGFloat(s.index) * C, y: L.origin.y - 6, width: C, height: h + 12)
            ctx.fill(Path(r), with: .color(colors.accent.opacity(0.3 * s.life)))
        }
        for b in game.blasts {
            let c = CGPoint(x: L.origin.x + (CGFloat(b.x) + 0.5) * C, y: L.origin.y + (CGFloat(b.y) + 0.5) * C)
            let r = C * (0.6 + 1.6 * (1 - b.life))
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(colors.accent.opacity(b.life)), lineWidth: 3 * b.life + 0.5)
        }

        // Pieces above the board are hidden until they fall in.
        ctx.drawLayer { l in
            l.clip(to: Path(CGRect(x: L.origin.x - 20, y: L.origin.y, width: w + 40, height: h + 40)))
            let hinted: Set<Int> = game.hint.map { h in Set([game.grid[h.a]?.id ?? -1, game.grid[h.b]?.id ?? -1]) } ?? Set<Int>()
            let beat = game.hint.map { 1 + 0.08 * sin($0.life * 14) } ?? 1
            for g in game.grid.compactMap({ $0 }) {
                var scale = g.grow * (game.pressed != nil && game.grid[game.pressed!]?.id == g.id ? 0.86 : 1)
                if hinted.contains(g.id) { scale *= beat }
                piece(&l, g, L, gap: gap, scale: scale, alpha: 1)
            }
            // The hint: an accent outline around the two squares to swap.
            if let h = game.hint {
                let a = h.a, b = h.b
                let x0 = min(a % game.cols, b % game.cols), y0 = min(a / game.cols, b / game.cols)
                let x1 = max(a % game.cols, b % game.cols), y1 = max(a / game.cols, b / game.cols)
                let r = CGRect(x: L.origin.x + CGFloat(x0) * C, y: L.origin.y + CGFloat(y0) * C,
                               width: CGFloat(x1 - x0 + 1) * C, height: CGFloat(y1 - y0 + 1) * C)
                l.stroke(Path(r), with: .color(colors.accent.opacity(min(1, h.life * 2))), lineWidth: 2)
            }
            for g in game.dying {
                piece(&l, g, L, gap: gap, scale: 1 + 0.35 * (1 - g.fade), alpha: g.fade)
            }
        }

        // Tutorial: when a power goes off, what it reaches glows before it goes: the row, the column,
        // the nine around the circle, or every square of the diamond's colour.
        if !game.regions.isEmpty {
            let pulse = 0.5 + 0.5 * sin(game.clock * 7)
            var area = Path()
            for r in game.regions {
                area.addRect(CGRect(x: L.origin.x + CGFloat(r.x0) * C, y: L.origin.y + CGFloat(r.y0) * C,
                                    width: CGFloat(r.x1 - r.x0 + 1) * C, height: CGFloat(r.y1 - r.y0 + 1) * C)
                    .insetBy(dx: -1, dy: -1))
            }
            // A soft light over the squares, then a glowing outline around the area.
            ctx.fill(area, with: .color(Color.white.opacity(0.16 + 0.14 * pulse)))
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: colors.accent.opacity(0.95), radius: 10 + 6 * pulse))
                l.addFilter(.shadow(color: colors.accent.opacity(0.6), radius: 3))
                l.stroke(area, with: .color(colors.accent), lineWidth: 2.5)
            }
            ctx.stroke(area, with: .color(Color.white.opacity(0.7 * pulse)), lineWidth: 1)
        }

        // Tutorial: outline the two squares to swap, and a finger showing the swipe.
        if let g = game.guide, !game.busy {
            let fx = g.cell % game.cols, fy = g.cell / game.cols
            let a = CGRect(x: L.origin.x + CGFloat(fx) * C, y: L.origin.y + CGFloat(fy) * C, width: C, height: C)
            let b = a.offsetBy(dx: CGFloat(g.dx) * C, dy: CGFloat(g.dy) * C)
            let pulse = 0.55 + 0.45 * sin(game.clock * 5)
            ctx.stroke(Path(a.union(b).insetBy(dx: 1, dy: 1)), with: .color(colors.ink.opacity(0.85 * pulse)), lineWidth: 2)
            let k = (game.clock * 0.9).truncatingRemainder(dividingBy: 1)
            let e = k < 0.7 ? 0.5 - 0.5 * cos(k / 0.7 * .pi) : 1
            let f = CGPoint(x: a.midX + (b.midX - a.midX) * CGFloat(e), y: a.midY + (b.midY - a.midY) * CGFloat(e))
            let fade = k < 0.75 ? 1 : max(0, 1 - (k - 0.75) / 0.25)
            let rr = C * 0.32
            ctx.fill(Path(ellipseIn: CGRect(x: f.x - rr, y: f.y - rr, width: rr * 2, height: rr * 2)),
                     with: .color(colors.ink.opacity(0.18 * fade)))
            ctx.stroke(Path(ellipseIn: CGRect(x: f.x - rr, y: f.y - rr, width: rr * 2, height: rr * 2)),
                       with: .color(colors.ink.opacity(0.7 * fade)), lineWidth: 1.5)
        }

        for p in game.particles {
            let x = L.origin.x + CGFloat(p.p.x) * C, y = L.origin.y + CGFloat(p.p.y) * C
            let s = C * 0.12
            ctx.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(shadeColor(Int(p.size)).opacity(p.life)))
        }
    }

    private func shadeColor(_ s: Int) -> Color {
        let pal = palette.isEmpty ? SwitchColors.palette(game.palette, colors) : palette
        return pal[min(pal.count - 1, max(0, s))]
    }

    private func piece(_ ctx: inout GraphicsContext, _ g: Gem, _ L: SwitchLayout, gap: CGFloat, scale: Double, alpha: Double) {
        let C = L.cell
        let size = (C - gap) * CGFloat(scale)
        let cx = L.origin.x + (CGFloat(g.x) + 0.5) * C, cy = L.origin.y + (CGFloat(g.y) + 0.5) * C
        let r = CGRect(x: cx - size / 2, y: cy - size / 2, width: size, height: size)
        let color = shadeColor(g.shade).opacity(alpha)
        let mark = colors.background.opacity(alpha)
        var shape = Path(r)
        switch g.power {
        case nil:
            ctx.fill(shape, with: .color(color))
            return
        case .row?, .column?:
            shape = Chamfer.path(in: r)
            ctx.fill(shape, with: .color(color))
            let len = r.width * 0.46, t = max(2, r.width * 0.07)
            let line = g.power == .row
                ? CGRect(x: r.midX - len / 2, y: r.midY - t / 2, width: len, height: t)
                : CGRect(x: r.midX - t / 2, y: r.midY - len / 2, width: t, height: len)
            ctx.fill(Path(line), with: .color(mark))
        case .bomb?:
            shape = Path(ellipseIn: r)
            ctx.fill(shape, with: .color(color))
            let d = r.width * 0.2
            ctx.fill(Path(ellipseIn: CGRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d)), with: .color(mark))
        case .shade?:
            var p = Path()
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.midY))
            p.closeSubpath()
            shape = p
            ctx.fill(shape, with: .color(color))
        }
        shine(&ctx, shape, r, id: g.id, alpha: alpha, strong: g.power == .shade)
    }

    /// Every power piece shines: a soft diagonal band of light sweeps across it from the top left,
    /// then rests, over and over (each piece at its own moment). The diamond's shine is brighter.
    private func shine(_ ctx: inout GraphicsContext, _ shape: Path, _ r: CGRect, id: Int, alpha: Double, strong: Bool) {
        let period = 1.9
        let t = (game.clock + Double(id % 9) * 0.37).truncatingRemainder(dividingBy: period) / period
        let sweep = 0.55                       // the part of each cycle the band is moving
        guard t < sweep else { return }
        let k = t / sweep
        let eased = k * k * (3 - 2 * k)
        // The band runs along the diagonal from top left to bottom right.
        let span = r.width + r.height
        let centre = -r.width * 0.3 + (span + r.width * 0.6) * CGFloat(eased)
        let half = r.width * 0.32
        var band = Path()
        band.move(to: CGPoint(x: r.minX + centre - half, y: r.minY))
        band.addLine(to: CGPoint(x: r.minX + centre + half, y: r.minY))
        band.addLine(to: CGPoint(x: r.minX + centre + half - r.height, y: r.maxY))
        band.addLine(to: CGPoint(x: r.minX + centre - half - r.height, y: r.maxY))
        band.closeSubpath()
        let peak = (strong ? 0.95 : 0.75) * alpha * sin(Double.pi * k)
        let a = CGPoint(x: r.minX + centre - half, y: r.minY + r.height / 2)
        let b = CGPoint(x: r.minX + centre + half, y: r.minY + r.height / 2)
        ctx.drawLayer { l in
            l.clip(to: shape)
            l.fill(band, with: .linearGradient(
                Gradient(stops: [
                    .init(color: Color.white.opacity(0), location: 0),
                    .init(color: Color.white.opacity(peak), location: 0.5),
                    .init(color: Color.white.opacity(0), location: 1),
                ]), startPoint: a, endPoint: b))
        }
    }
}

/// The Switch landing page: six squares over S W I T C H, the powers, and Start.
struct SwitchHome: View {
    let game: SwitchGame
    let colors: Colors
    let onBack: () -> Void
    let onSettings: () -> Void

    @State private var dropped = false
    @State private var drag: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            BackBar(ink: colors.ink, settings: onSettings, action: onBack)
            Spacer()
            ElasticLogo(word: "SWITCH",
                        fills: SwitchColors.logo(colors),
                        ink: colors.ink, drag: drag, dropped: dropped)
            rules.padding(.top, 34)
            Spacer(minLength: 16)
            Text(result)
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(colors.ink.opacity(0.5))
                .frame(minHeight: 20)
            Spacer(minLength: 16)
            Spacer(minLength: 16)
            // Two ways to play: shades of one colour, or five colours from the theme.
            HStack(spacing: 12) {
                OutlineButton(title: "Mono", colors: colors, width: 140) { game.start(.mono) }
                OutlineButton(title: "Colour", colors: colors, width: 140) { game.start(.colour) }
            }
            .padding(.bottom, 64)
        }
        .elasticDrag($drag)
        .onAppear {
            dropped = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55)) { dropped = true }
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 12) {
            rule(threeMark, "Swipe to swap. Line up three of a shade")
            rule(lineMark(across: true), "Four across: clears its row")
            rule(lineMark(across: false), "Four down: clears its column")
            rule(bombMark, "Five in a line: clears the squares around it")
            rule(diamondMark, "A T or an L: clears every square of its shade")
        }
    }

    private var threeMark: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in Rectangle().fill(colors.accent).frame(width: 7, height: 7) }
        }
    }

    private func lineMark(across: Bool) -> some View {
        ZStack {
            ChamferShape().fill(colors.accent)
            Rectangle().fill(colors.background).frame(width: across ? 7 : 1.5, height: across ? 1.5 : 7)
        }
        .frame(width: 15, height: 15)
    }

    private var bombMark: some View {
        ZStack {
            Circle().fill(colors.accent)
            Circle().fill(colors.background).frame(width: 3, height: 3)
        }
        .frame(width: 15, height: 15)
    }

    private var diamondMark: some View {
        ZStack {
            Rectangle().fill(colors.accent).frame(width: 11, height: 11).rotationEffect(.degrees(45))
            Rectangle().fill(colors.background).frame(width: 2.5, height: 2.5)
        }
        .frame(width: 16, height: 16)
    }

    private func rule(_ mark: some View, _ text: String) -> some View {
        HStack(spacing: 12) {
            mark.frame(width: 26, height: 16, alignment: .leading)
            Text(text).font(.system(size: 13)).foregroundStyle(colors.ink.opacity(0.6))
        }
    }

    private var result: String {
        let best = Settings.shared.switchBest
        guard let s = game.lastScore else { return best > 0 ? "Best \(best)" : " " }
        if !Unlock.shared.isUnlocked { return "\(s) · unlock to keep your best" }
        return game.newBest ? "New best · \(s)" : "\(s) · best \(best)"
    }
}
