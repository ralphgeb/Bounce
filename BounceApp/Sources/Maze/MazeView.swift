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
                // Zoomed in: about seven tiles across the screen.
                let scene = MazeRenderer.Scene(
                    maze: game.maze, pos: game.pos, light: game.light, lit: game.lit, dots: game.dots,
                    range: game.range, tile: size.width / 7,
                    moving: game.moving, squash: game.squash, bump: game.bump, flash: game.flash,
                    time: game.totalTime, revealWalls: Settings.shared.mazeRevealWalls)
                MazeRenderer.draw(&ctx, size: size, scene: scene, colors: colors)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
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
                    .onEnded { v in
                        // A tap (no swipe): drop or pick up a dot.
                        if !swiped && hypot(v.translation.width, v.translation.height) < 12 { game.tap() }
                        swiped = false
                    }
            )

            VStack(spacing: 0) {
                hud
                Spacer()
                if game.level == 1 && game.levelTime < 5 {
                    Text("Swipe to move · tap to drop a dot")
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(3)
                        .textCase(.uppercase)
                        .foregroundStyle(colors.ink.opacity(0.4))
                        .padding(.bottom, 40)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.4), value: game.levelTime < 5)

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
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(game.level)")
                        .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(colors.ink)
                        .contentTransition(.numericText())
                    Text("/\(Maze.levels)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(colors.ink.opacity(0.35))
                }
                HStack(spacing: 5) {
                    Circle().fill(colors.accent).frame(width: 6, height: 6)
                    Text("\(game.dotsLeft)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(colors.ink.opacity(0.55))
                }
                .padding(.top, 6)
                .accessibilityElement()
                .accessibilityLabel("\(game.dotsLeft) dots left")
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

/// The Maze landing page: four squares over M A Z E, how to play, and Start.
struct MazeHome: View {
    let game: MazeGame
    let colors: Colors
    let onBack: () -> Void
    let onSettings: () -> Void

    @State private var dropped = false
    @State private var drag: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                BackBar(ink: colors.ink, settings: onSettings, action: onBack)
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
            rule(Rectangle().fill(colors.accent).frame(width: 12, height: 12), "You. Swipe to slide to the next turning")
            rule(glowMark, "Your light shines all around. Walls cast shadows")
            rule(Circle().fill(colors.accent).frame(width: 5, height: 5), "Tap to drop a dot, tap again to pick it up")
            rule(goalMark, "Reach the glow to go deeper. 20 levels")
        }
    }

    private var glowMark: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [colors.ink.opacity(0.8), colors.ink.opacity(0)], center: .center, startRadius: 0, endRadius: 9))
            Rectangle().fill(colors.accent).frame(width: 5, height: 5)
        }
        .frame(width: 18, height: 18)
    }

    private var goalMark: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [colors.accent.opacity(0.6), colors.accent.opacity(0)], center: .center, startRadius: 0, endRadius: 9))
            Circle().fill(colors.accent).frame(width: 7, height: 7)
        }
        .frame(width: 18, height: 18)
    }

    private func rule(_ mark: some View, _ text: String) -> some View {
        HStack(spacing: 12) {
            mark.frame(width: 20, height: 16)
            Text(text).font(.system(size: 13)).foregroundStyle(colors.ink.opacity(0.65))
        }
    }

    private var result: String {
        let s = Settings.shared
        if let r = game.lastRun, r.level >= Maze.levels, s.mazeFinished, game.newRecord {
            return "Out of all 20 levels · \(formatTime(r.time))"
        }
        if let r = game.lastRun {
            let deepest = max(s.mazeDeepest, r.level)
            return r.level >= deepest && game.newRecord
                ? "New deepest · level \(r.level) · \(formatTime(r.time))"
                : "Level \(r.level) · \(formatTime(r.time)) · deepest \(deepest)"
        }
        return s.mazeDeepest > 1 ? "Deepest level \(s.mazeDeepest)" : " "
    }
}
