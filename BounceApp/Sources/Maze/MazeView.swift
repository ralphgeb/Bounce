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
                // Zoomed in: about seven tiles across. On the map, out to the whole maze.
                let m = game.maze
                let near = size.width / 7
                let far = min(size.width / CGFloat(m.width + 2), (size.height - 160) / CGFloat(m.height + 2))
                let z = CGFloat(game.map)
                let tile = near + (far - near) * z
                let middle = CGPoint(x: Double(m.width) / 2, y: Double(m.height) / 2 + 1.2)
                let camera = CGPoint(x: game.pos.x + (middle.x - game.pos.x) * z, y: game.pos.y + (middle.y - game.pos.y) * z)
                var scene = MazeRenderer.Scene(
                    maze: m, pos: game.pos, light: game.light, lit: game.lit, dots: game.dots,
                    range: game.range, tile: tile,
                    moving: game.moving, squash: game.squash, bump: game.bump, flash: game.flash,
                    time: game.totalTime, revealWalls: Settings.shared.mazeRevealWalls)
                scene.map = game.map
                scene.seen = game.seen
                scene.camera = camera
                scene.dotGain = game.dotGain
                scene.dotGainAge = game.dotGainAge
                MazeRenderer.draw(&ctx, size: size, scene: scene, colors: colors)
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        // One move per swipe, as soon as the finger has clearly picked a direction.
                        guard !swiped, game.map < 0.05 else { return }
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
                        if !swiped && game.map < 0.05 && hypot(v.translation.width, v.translation.height) < 12 {
                            game.tap()
                        }
                        swiped = false
                    }
            )
            .simultaneousGesture(
                // Pinch in to zoom out to the map; let go and it zooms back.
                MagnifyGesture()
                    .onChanged { v in game.pinch(Double((1 - v.magnification) * 2.2)) }
                    .onEnded { _ in game.endPinch() }
            )

            VStack(spacing: 0) {
                hud
                Spacer()
                if game.level == 1 && game.levelTime < 6 && !game.coach.active {
                    VStack(spacing: 8) {
                        ForEach(["Swipe to move", "Tap to drop a dot", "Pinch to see the map"], id: \.self) { line in
                            Text(line)
                                .font(.system(size: 12, weight: .semibold))
                                .tracking(2.4)
                                .textCase(.uppercase)
                                .foregroundStyle(colors.ink.opacity(0.45))
                        }
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 44)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.4), value: game.levelTime < 6)

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

            // The tutorial steps aside while paused; Carry on sits on top.
            if game.phase != .paused { CoachOverlay(coach: game.coach, colors: colors) }
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
                    Circle().fill(colors.accent).frame(width: 7, height: 7)
                        .shadow(color: colors.accent.opacity(0.8), radius: 4)
                    Text("\(game.dotsLeft)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(colors.ink.opacity(0.6))
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: game.dotsLeft)
                    DotGainBadge(amount: game.dotGain, id: game.dotGainID, colors: colors)
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

/// "+3": pops up next to the dots count when new dots arrive, then fades.
private struct DotGainBadge: View {
    let amount: Int
    let id: Int
    let colors: Colors
    @State private var shown = false

    var body: some View {
        Text("+\(amount)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(colors.accent)
            .scaleEffect(shown ? 1 : 0.4)
            .opacity(shown ? 1 : 0)
            .onChange(of: id, initial: true) {
                guard amount > 0 else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { shown = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(.easeOut(duration: 0.4)) { shown = false }
                }
            }
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
            rule(Circle().fill(colors.accent).frame(width: 6, height: 6), "Tap to drop a dot, tap again to pick it up")
            rule(mapMark, "Pinch to see the map")
            rule(goalMark, "Reach the star to go deeper. 20 levels")
        }
    }

    private var glowMark: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [colors.ink.opacity(0.8), colors.ink.opacity(0)], center: .center, startRadius: 0, endRadius: 9))
            Rectangle().fill(colors.accent).frame(width: 5, height: 5)
        }
        .frame(width: 18, height: 18)
    }

    private var mapMark: some View {
        ZStack {
            Rectangle().strokeBorder(colors.ink.opacity(0.6), lineWidth: 1.5)
            Rectangle().fill(colors.accent).frame(width: 4, height: 4).offset(x: -2, y: 2)
        }
        .frame(width: 14, height: 14)
    }

    private var goalMark: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [colors.accent.opacity(0.6), colors.accent.opacity(0)], center: .center, startRadius: 0, endRadius: 9))
            StarShape().fill(colors.accent).frame(width: 12, height: 12)
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
