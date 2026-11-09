import SwiftUI

/// Playing Hue: the board, the level and swaps.
struct HueView: View {
    let game: HueGame
    let colors: Colors

    @State private var downPlace: Int?
    @State private var moved = false

    var body: some View {
        let frame = game.frame
        GeometryReader { geo in
            let L = SwitchLayout(size: geo.size, cols: game.cols, rows: game.rows)
            ZStack {
                Canvas { ctx, _ in
                    _ = frame
                    draw(&ctx, L)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if downPlace == nil {
                                downPlace = L.cellAt(v.startLocation, cols: game.cols, rows: game.rows)
                                moved = false
                            }
                            if hypot(v.translation.width, v.translation.height) > 8 { moved = true }
                            if moved, let p = downPlace { game.drag(from: p, to: v.location) }
                        }
                        .onEnded { v in
                            if moved {
                                game.drop(on: L.cellAt(v.location, cols: game.cols, rows: game.rows))
                            } else if let p = downPlace {
                                game.tap(p)
                            }
                            downPlace = nil
                            moved = false
                        }
                )

                VStack(spacing: 0) {
                    hud
                    Spacer()
                    if game.phase == .preview {
                        Text("Remember it")
                            .font(.system(size: 12, weight: .semibold))
                            .tracking(3)
                            .textCase(.uppercase)
                            .foregroundStyle(colors.ink.opacity(0.5))
                            .padding(.bottom, 40)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.3), value: game.phase == .preview)

                if game.phase == .solved && !game.inTutorial { solvedCard.transition(.opacity.combined(with: .scale(scale: 0.96))) }
                // The tutorial steps aside while paused; Carry on sits on top.
                if game.phase != .paused { CoachOverlay(coach: game.coach, colors: colors) }
                if game.phase == .paused { paused }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: game.phase == .solved)
        .sheet(isPresented: Binding(get: { game.askUnlock }, set: { game.askUnlock = $0 })) {
            UnlockSheet(colors: colors)
        }
    }

    private var hud: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Level").bounceLabel(colors)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(game.number)")
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(colors.ink)
                    Text("/\(HueLevels.count)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(colors.ink.opacity(0.35))
                }
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
                Text("Swaps").bounceLabel(colors)
                Text("\(game.swaps)")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(colors.ink.opacity(0.35))
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    private var solvedCard: some View {
        VStack(spacing: 0) {
            Spacer()
            // The stars, big and glowing, as in Maze, on a panel of their own.
            VStack(spacing: 16) {
                HStack(spacing: 14) {
                    ForEach(0..<3, id: \.self) { i in
                        let won = i < game.stars
                        StarShape()
                            .fill(won ? colors.accent : colors.ink.opacity(0.15))
                            .frame(width: 38, height: 38)
                            .shadow(color: won ? colors.accent.opacity(0.75) : .clear, radius: 10)
                            .scaleEffect(won ? 1 : 0.85)
                    }
                }
                Text("Level \(game.number) · \(game.swaps) swaps · fewest \(game.fewestSwaps)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(colors.ink.opacity(0.75))
                Text(game.stars == 3 ? "Perfect" : "Three stars: the fewest swaps")
                    .font(.system(size: 12))
                    .foregroundStyle(colors.ink.opacity(0.5))
            }
            .padding(.vertical, 24)
            .padding(.horizontal, 26)
            .background(colors.background.opacity(0.92))
            .overlay(Rectangle().strokeBorder(colors.ink.opacity(0.08), lineWidth: 1))
            .padding(.bottom, 22)
            if game.number < HueLevels.count {
                OutlineButton(title: "Next level", colors: colors) { game.next() }
            } else {
                Text("All \(HueLevels.count) levels done")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.ink.opacity(0.5))
            }
            Button("Levels") { game.home() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.ink.opacity(0.5))
                .padding(.top, 12)
                .padding(.bottom, 40)
        }
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
                Button("Levels") { game.home() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.ink.opacity(0.5))
            }
        }
        .transition(.opacity)
    }

    // MARK: Drawing

    private func draw(_ ctx: inout GraphicsContext, _ L: SwitchLayout) {
        let C = L.cell
        let gap = C * 0.08
        let n = game.cols * game.rows
        guard game.colors.count == n, game.tiles.count == n else { return }
        let draggedID = game.dragging.map { game.order[$0.place] }

        func tileRect(_ t: HueGame.Tile, scale: CGFloat) -> CGRect {
            let s = (C - gap) * scale
            let cx = L.origin.x + (CGFloat(t.x) + 0.5) * C, cy = L.origin.y + (CGFloat(t.y) + 0.5) * C
            return CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s)
        }

        for place in 0..<n {
            let id = game.order[place]
            guard id != draggedID else { continue }
            let t = game.tiles[id]
            var scale = 1 + 0.08 * CGFloat(t.lift)
            // Solved: a wave runs across the board from the top left.
            if game.phase == .solved {
                let d = Double(t.x + t.y) * 0.06
                let w = max(0, min(1, (game.solvedAge - d) / 0.35))
                scale *= 1 + 0.14 * CGFloat(sin(w * .pi))
            }
            let r = tileRect(t, scale: scale)
            ctx.fill(Path(r), with: .color(game.colors[id].color))
            if game.isFixed(place) {
                // A small dot on fixed squares, dark on light colours and light on dark ones.
                let c = game.colors[id]
                let lum = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
                let d = C * 0.1
                ctx.fill(Path(ellipseIn: CGRect(x: r.midX - d / 2, y: r.midY - d / 2, width: d, height: d)),
                         with: .color(lum > 0.55 ? Color.black.opacity(0.55) : Color.white.opacity(0.75)))
            }
            if game.picked == place {
                ctx.stroke(Path(r.insetBy(dx: -3, dy: -3)), with: .color(colors.ink), lineWidth: 2)
            }
        }

        // Tutorial: outline a square and where it belongs, with a finger showing the drag.
        if let g = game.guide, game.dragging == nil {
            func cellRect(_ p: Int) -> CGRect {
                CGRect(x: L.origin.x + CGFloat(p % game.cols) * C, y: L.origin.y + CGFloat(p / game.cols) * C, width: C, height: C)
            }
            let a = cellRect(g.from), b = cellRect(g.to)
            let pulse = 0.55 + 0.45 * sin(game.clock * 5)
            ctx.stroke(Path(a.insetBy(dx: 1, dy: 1)), with: .color(colors.ink.opacity(0.9 * pulse)), lineWidth: 2)
            ctx.stroke(Path(b.insetBy(dx: 1, dy: 1)), with: .color(colors.ink.opacity(0.5 * pulse)),
                       style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            let k = (game.clock * 0.7).truncatingRemainder(dividingBy: 1)
            let e = k < 0.7 ? 0.5 - 0.5 * cos(k / 0.7 * .pi) : 1
            let f = CGPoint(x: a.midX + (b.midX - a.midX) * CGFloat(e), y: a.midY + (b.midY - a.midY) * CGFloat(e))
            let fade = k < 0.78 ? 1 : max(0, 1 - (k - 0.78) / 0.22)
            let rr = C * 0.34
            ctx.fill(Path(ellipseIn: CGRect(x: f.x - rr, y: f.y - rr, width: rr * 2, height: rr * 2)), with: .color(colors.ink.opacity(0.2 * fade)))
            ctx.stroke(Path(ellipseIn: CGRect(x: f.x - rr, y: f.y - rr, width: rr * 2, height: rr * 2)),
                       with: .color(colors.ink.opacity(0.75 * fade)), lineWidth: 1.5)
        }

        // The square being dragged, lifted, under the finger.
        if let d = game.dragging, let id = draggedID {
            let s = (C - gap) * 1.18
            let r = CGRect(x: d.point.x - s / 2, y: d.point.y - s / 2, width: s, height: s)
            ctx.fill(Path(r.offsetBy(dx: 0, dy: 6)), with: .color(Color.black.opacity(0.18)))
            ctx.fill(Path(r), with: .color(game.colors[id].color))
            // Where it would land.
            if let target = L.cellAt(d.point, cols: game.cols, rows: game.rows), target != d.place, !game.isFixed(target) {
                let tr = CGRect(x: L.origin.x + CGFloat(target % game.cols) * C + gap / 2,
                                y: L.origin.y + CGFloat(target / game.cols) * C + gap / 2, width: C - gap, height: C - gap)
                ctx.stroke(Path(tr.insetBy(dx: -2, dy: -2)), with: .color(colors.ink.opacity(0.6)), lineWidth: 1.5)
            }
        }
    }
}

/// The Hue landing page: three shades of the accent over H U E, the fifty levels to pick from, and Start.
struct HueHome: View {
    let game: HueGame
    let colors: Colors
    let onBack: () -> Void
    let onSettings: () -> Void

    @State private var dropped = false
    @State private var drag: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let s = Settings.shared
        VStack(spacing: 0) {
            BackBar(ink: colors.ink, settings: onSettings, action: onBack)
            Spacer()
            ElasticLogo(word: "HUE", fills: HueColor.logo(colors.accent),
                        ink: colors.ink, drag: drag, dropped: dropped)
            VStack(alignment: .leading, spacing: 12) {
                rule(gradientMark, "Swap squares to put the colours back in order")
                rule(dotMark, "Squares with a dot are fixed")
            }
            .padding(.top, 34)
            levels.padding(.top, 34)
            Spacer(minLength: 16)
            Text(result)
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(colors.ink.opacity(0.5))
                .frame(minHeight: 20)
            Spacer(minLength: 16)
            Spacer(minLength: 16)
            OutlineButton(title: "Level \(game.chosen)", colors: colors) { game.start() }
                .padding(.bottom, 64)
        }
        .elasticDrag($drag)
        .sheet(isPresented: Binding(get: { game.askUnlock }, set: { game.askUnlock = $0 })) {
            UnlockSheet(colors: colors)
        }
        .onAppear {
            let cap = Unlock.shared.isUnlocked ? HueLevels.count : Unlock.freeLevels
            game.chosen = min(cap, max(game.chosen, s.hueSolved + 1))
            dropped = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55)) { dropped = true }
        }
    }

    /// The fifty levels as a grid of squares, ten a row: solved ones filled (light to deep shades
    /// of the accent), the next one open, the rest locked.
    private var levels: some View {
        let solved = Settings.shared.hueSolved
        let grid = Array(repeating: GridItem(.fixed(24), spacing: 5), count: 10)
        return LazyVGrid(columns: grid, spacing: 14) {
            ForEach(1...HueLevels.count, id: \.self) { n in
                let locked = n > Unlock.freeLevels && !Unlock.shared.isUnlocked
                let open = n <= solved + 1 && !locked
                let fill = HueColor.shade(colors.accent, 0.5 - Double(n - 1) / Double(HueLevels.count - 1))
                Button {
                    if locked { game.askUnlock = true; return }
                    guard open else { Haptics.tap(.soft, intensity: 0.3); return }
                    game.chosen = n
                    Haptics.tap(.light)
                } label: {
                    ZStack {
                        Rectangle().fill(n <= solved ? fill : colors.ink.opacity(open ? 0.08 : 0.03))
                        if game.chosen == n {
                            Rectangle().strokeBorder(colors.ink, lineWidth: 1.5).padding(-3)
                        }
                        if locked {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(colors.ink.opacity(0.3))
                        } else {
                            Text("\(n)")
                                .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(n <= solved ? Color.white.opacity(0.9) : colors.ink.opacity(open ? 0.6 : 0.2))
                        }
                    }
                    .frame(width: 24, height: 24)
                    // The stars won, as three small marks under the square.
                    .overlay(alignment: .bottom) {
                        let won = Settings.shared.hueStars[String(n)] ?? 0
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { i in
                                Rectangle().fill(i < won ? colors.accent : colors.ink.opacity(0.12)).frame(width: 4, height: 2)
                            }
                        }
                        .offset(y: 9)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(open ? "Level \(n)" : "Level \(n), locked")
            }
        }
    }

    private var gradientMark: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Rectangle().fill(HueColor.logo(colors.accent)[i]).frame(width: 7, height: 7)
            }
        }
    }

    private var dotMark: some View {
        ZStack {
            Rectangle().fill(colors.ink.opacity(0.3)).frame(width: 14, height: 14)
            Circle().fill(colors.ink).frame(width: 4, height: 4)
        }
    }

    private func rule(_ mark: some View, _ text: String) -> some View {
        HStack(spacing: 12) {
            mark.frame(width: 26, height: 16, alignment: .leading)
            Text(text).font(.system(size: 13)).foregroundStyle(colors.ink.opacity(0.6))
        }
    }

    private var result: String {
        let s = Settings.shared
        let total = s.hueStars.values.reduce(0, +)
        if let b = s.hueBest[String(game.chosen)] {
            return "Level \(game.chosen) · best \(b) swaps · \(total) of \(HueLevels.count * 3) stars"
        }
        return s.hueSolved >= HueLevels.count ? "All \(HueLevels.count) solved" : " "
    }
}
