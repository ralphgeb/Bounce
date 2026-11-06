import SwiftUI

/// Playing Maze: the dark board under your finger, the level and time on top.
struct MazeView: View {
    let game: MazeGame
    let colors: Colors

    @State private var swiped = false

    var body: some View {
        let frame = game.frame
        ZStack {
            Canvas { ctx, size in
                _ = frame
                let scene = MazeRenderer.Scene(
                    maze: game.maze, pos: game.pos, cone: game.cone, halo: game.halo, lit: game.lit,
                    seen: game.seen, range: game.coneRange, tile: size.width / 11,
                    moving: game.moving, squash: game.squash, bump: game.bump, flash: game.flash,
                    time: game.levelTime)
                MazeRenderer.draw(&ctx, size: size, scene: scene, colors: colors)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { v in
                        // One move per swipe, as soon as the finger has clearly picked a direction.
                        guard !swiped else { return }
                        let t = v.translation
                        guard hypot(t.width, t.height) > 22 else { return }
                        swiped = true
                        if abs(t.width) > abs(t.height) {
                            game.swipe(t.width > 0 ? .right : .left)
                        } else {
                            game.swipe(t.height > 0 ? .down : .up)
                        }
                    }
                    .onEnded { _ in swiped = false }
            )

            VStack(spacing: 0) {
                hud
                Spacer()
                if game.level == 1 && game.levelTime < 4 {
                    Text("Swipe to move")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(3)
                        .textCase(.uppercase)
                        .foregroundStyle(colors.ink.opacity(0.4))
                        .padding(.bottom, 40)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.4), value: game.levelTime < 4)

            if let t = game.toast {
                Text(t.uppercased())
                    .font(.system(size: 13, weight: .bold))
                    .tracking(4)
                    .foregroundStyle(colors.accent)
                    .offset(y: -90)
                    .id(game.toastID)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .allowsHitTesting(false)
            }

            if game.phase == .paused { paused }
        }
        .animation(.easeOut(duration: 0.25), value: game.toastID)
    }

    private var hud: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Level").bounceLabel(colors)
                Text("\(game.level)")
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
                Text("Time").bounceLabel(colors)
                Text(formatTime(game.levelTime))
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
                Button("End run") { game.home() }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(colors.ink.opacity(0.5))
            }
        }
        .transition(.opacity)
    }
}

/// The Maze landing page: four squares over M A Z E, the light sweeping behind, and Start.
struct MazeHome: View {
    let game: MazeGame
    let colors: Colors
    let onBack: () -> Void

    @State private var dropped = false
    @State private var drag: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MazePreview(colors: colors, tilesAcross: 11, strength: 0.55)
                .ignoresSafeArea()
                .overlay(
                    LinearGradient(colors: [colors.background.opacity(0.2), colors.background.opacity(0.75), colors.background.opacity(0.2)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                )
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                BackBar(ink: colors.ink, action: onBack)
                Spacer()
                ElasticLogo(word: "MAZE", fills: [colors.ink, colors.accent, colors.ink.opacity(0.5), colors.ink.opacity(0.22)],
                            ink: colors.ink, drag: drag, dropped: dropped)
                rules.padding(.top, 34)
                Spacer(minLength: 16)
                Text(result)
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundStyle(colors.ink.opacity(0.55))
                    .frame(minHeight: 20)
                Spacer(minLength: 16)
                Spacer(minLength: 16)
                OutlineButton(title: game.lastRun == nil ? "Start" : "Again", colors: colors) { game.start() }
                    .padding(.bottom, 64)
            }
        }
        .elasticDrag($drag)
        .onAppear {
            dropped = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55)) { dropped = true }
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 12) {
            rule(Rectangle().fill(colors.accent).frame(width: 14, height: 14), "You. Swipe to slide to the next turning")
            rule(coneMark, "Your light shows the way. Walls cast shadows")
            rule(Circle().fill(colors.accent).frame(width: 12, height: 12), "Reach the light to go one level deeper")
        }
    }

    private var coneMark: some View {
        Canvas { ctx, size in
            var p = Path()
            p.move(to: CGPoint(x: 0, y: size.height / 2))
            p.addLine(to: CGPoint(x: size.width, y: 0))
            p.addLine(to: CGPoint(x: size.width, y: size.height))
            p.closeSubpath()
            ctx.fill(p, with: .linearGradient(Gradient(colors: [colors.ink.opacity(0.9), colors.ink.opacity(0.05)]),
                                              startPoint: CGPoint(x: 0, y: size.height / 2), endPoint: CGPoint(x: size.width, y: size.height / 2)))
        }
        .frame(width: 18, height: 14)
    }

    private func rule(_ mark: some View, _ text: String) -> some View {
        HStack(spacing: 12) {
            mark.frame(width: 20, height: 16)
            Text(text).font(.system(size: 13)).foregroundStyle(colors.ink.opacity(0.65))
        }
    }

    private var result: String {
        let s = Settings.shared
        if let r = game.lastRun {
            let deepest = max(s.mazeDeepest, r.level)
            return r.level >= deepest && game.newRecord
                ? "New deepest · level \(r.level) · \(formatTime(r.time))"
                : "Level \(r.level) · \(formatTime(r.time)) · deepest \(deepest)"
        }
        return s.mazeDeepest > 1 ? "Deepest level \(s.mazeDeepest)" : " "
    }
}
