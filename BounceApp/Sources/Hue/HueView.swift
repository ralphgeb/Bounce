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

                if game.phase == .solved { solvedCard.transition(.opacity.combined(with: .scale(scale: 0.96))) }
                if game.phase == .paused { paused }
                CoachOverlay(coach: game.coach, colors: colors)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: game.phase == .solved)
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
        VStack(spacing: 18) {
            Spacer()
            Text(game.newBest ? "Solved · \(game.swaps) swaps · best" : "Solved · \(game.swaps) swaps")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(colors.ink.opacity(0.7))
            if game.number < HueLevels.count {
                OutlineButton(title: "Next level", colors: colors) { game.next() }
            } else {
                Text("All ten levels done")
                    .font(.system(size: 13))
                    .foregroundStyle(colors.ink.opacity(0.5))
            }
            Button("Levels") { game.home() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.ink.opacity(0.5))
                .padding(.bottom, 50)
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

/// The Hue landing page: three squares over H U E, the ten levels to pick from, and Start.
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
        let second = s.secondAccent.color
        VStack(spacing: 0) {
            BackBar(ink: colors.ink, settings: onSettings, action: onBack)
            Spacer()
            ElasticLogo(word: "HUE", fills: [colors.accent, HueColor.mix(colors.accent, second, 0.5), second],
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
        .onAppear {
            game.chosen = min(HueLevels.count, max(game.chosen, s.hueSolved + 1))
            dropped = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55)) { dropped = true }
        }
    }

    /// The ten levels as a row of squares: solved ones filled, the next one open, the rest locked.
    private var levels: some View {
        let solved = Settings.shared.hueSolved
        let second = Settings.shared.secondAccent.color
        return HStack(spacing: 6) {
            ForEach(1...HueLevels.count, id: \.self) { n in
                let open = n <= solved + 1
                let fill = HueColor.mix(colors.accent, second, Double(n - 1) / Double(HueLevels.count - 1))
                Button {
                    guard open else { Haptics.tap(.soft, intensity: 0.3); return }
                    game.chosen = n
                    Haptics.tap(.light)
                } label: {
                    ZStack {
                        Rectangle().fill(n <= solved ? fill : colors.ink.opacity(open ? 0.08 : 0.03))
                        if game.chosen == n {
                            Rectangle().strokeBorder(colors.ink, lineWidth: 1.5).padding(-3)
                        }
                        Text("\(n)")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(n <= solved ? Color.white.opacity(0.9) : colors.ink.opacity(open ? 0.6 : 0.2))
                    }
                    .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(open ? "Level \(n)" : "Level \(n), locked")
            }
        }
    }

    private var gradientMark: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Rectangle().fill(HueColor.mix(colors.accent, Settings.shared.secondAccent.color, Double(i) / 2)).frame(width: 7, height: 7)
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
        if let b = s.hueBest[String(game.chosen)] { return "Level \(game.chosen) · best \(b) swaps" }
        return s.hueSolved >= HueLevels.count ? "All ten solved" : " "
    }
}
