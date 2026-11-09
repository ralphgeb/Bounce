import SwiftUI
import UIKit

/// Playing Maze: the dark board under your finger, the level and time on top.
struct MazeView: View {
    let game: MazeGame
    let colors: Colors

    @State private var swiped = false

    var body: some View {
        let frame = game.frame
        ZStack {
            // While a map square shows the whole maze, the board is kept out of screenshots.
            Group {
                if game.revealLeft > 0 {
                    ScreenshotProof(content: board(frame))
                } else {
                    board(frame)
                }
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
                    // Zoomed out, a soft fade behind the score keeps it readable over the map.
                    .background(alignment: .top) {
                        LinearGradient(colors: [colors.background, colors.background.opacity(0.9), colors.background.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 220)
                            .ignoresSafeArea()
                            .opacity(game.map)
                            .allowsHitTesting(false)
                    }
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

            // Level done: the stars won, and slides against the fewest possible.
            if game.phase == .cleared && !game.inTutorial {
                levelDone
                    .id(game.starsID)
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }

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

    /// The maze itself, drawn for this frame.
    private func board(_ frame: Int) -> some View {
        Canvas { ctx, size in
            _ = frame
            // Zoomed in: about seven tiles across. On the map, out to the whole maze.
            let m = game.maze
            let near = size.width / 7
            // The map fits below the score and above the bottom edge, so nothing covers the text.
            let far = min(size.width / CGFloat(m.width + 2), (size.height - 300) / CGFloat(m.height + 2))
            let z = CGFloat(game.map)
            var tile = near + (far - near) * z
            let lift = Double(70 / max(far, 1))     // nudge the map down, clear of the score
            let middle = CGPoint(x: Double(m.width) / 2, y: Double(m.height) / 2 - lift)
            var camera = CGPoint(x: game.pos.x + (middle.x - game.pos.x) * z, y: game.pos.y + (middle.y - game.pos.y) * z)
            if game.inTutorial {
                // The tutorial's maze stays still, fitted to the width and set low, so the
                // instructions above never cover it.
                tile = size.width / CGFloat(m.width + 1) * (1 - 0.35 * z)
                camera = CGPoint(x: Double(m.width) / 2, y: Double(m.height) / 2 - 1.6)
            }
            var scene = MazeRenderer.Scene(
                maze: m, pos: game.pos, light: game.light, lit: game.lit, dots: game.dots,
                range: game.range, tile: tile,
                moving: game.moving, squash: game.squash, bump: game.bump, flash: game.flash,
                time: game.totalTime)
            scene.map = game.map
            scene.seen = game.seen
            scene.camera = camera
            scene.dotGain = game.dotGain
            scene.dotGainAge = game.dotGainAge
            scene.blink = game.blink
            scene.reveals = game.reveals
            scene.revealAll = game.revealLeft > 0 ? min(1, game.map * 1.2) : 0
            MazeRenderer.draw(&ctx, size: size, scene: scene, colors: colors)
        }
    }

    private var levelDone: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { i in
                    let won = i < game.lastStars
                    StarShape()
                        .fill(won ? colors.accent : colors.ink.opacity(0.15))
                        .frame(width: 34, height: 34)
                        .shadow(color: won ? colors.accent.opacity(0.7) : .clear, radius: 10)
                        .scaleEffect(won ? 1 : 0.85)
                }
            }
            Text("Level \(game.level) · \(game.slides) slides · fewest \(game.fewestSlides)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(colors.ink.opacity(0.75))
            Text(game.lastStars == 3 ? "Perfect" : game.lastStars == 2 ? "Three stars: fewer slides, a little faster" : "Three stars: close to the fewest slides, in time")
                .font(.system(size: 12))
                .foregroundStyle(colors.ink.opacity(0.5))
        }
        .padding(.vertical, 26)
        .padding(.horizontal, 24)
        .background(colors.background.opacity(0.85))
        .allowsHitTesting(false)
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
                // How far the star is, walking, until you're close; then it's up to you.
                Group {
                    if game.showsDistance {
                        Text("\(game.stepsToStar) to the star")
                            .contentTransition(.numericText())
                    } else {
                        Text("Close. Find it.")
                    }
                }
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(colors.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                // The tutorial points at it: a pulsing outline.
                .overlay {
                    if game.coach.current?.pointer == .counter {
                        PulsingFrame(color: colors.accent)
                    }
                }
                .padding(.top, 2)
                .animation(.easeOut(duration: 0.3), value: game.stepsToStar)
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

/// Hides what's inside from screenshots and screen recordings (it comes out blank), using the
/// protected layer iOS draws password fields in.
struct ScreenshotProof<Content: View>: UIViewRepresentable {
    let content: Content

    func makeCoordinator() -> UIHostingController<Content> { UIHostingController(rootView: content) }

    func makeUIView(context: Context) -> UIView {
        let host = context.coordinator.view!
        host.backgroundColor = .clear
        let field = UITextField()
        field.isSecureTextEntry = true
        guard let secure = field.layer.sublayers?.first?.delegate as? UIView else { return host }
        secure.subviews.forEach { $0.removeFromSuperview() }
        secure.isUserInteractionEnabled = false
        host.translatesAutoresizingMaskIntoConstraints = false
        secure.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: secure.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: secure.trailingAnchor),
            host.topAnchor.constraint(equalTo: secure.topAnchor),
            host.bottomAnchor.constraint(equalTo: secure.bottomAnchor),
        ])
        return secure
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.rootView = content
    }
}

/// An outline that breathes, to point something out.
private struct PulsingFrame: View {
    let color: Color
    @State private var on = false
    var body: some View {
        Rectangle()
            .strokeBorder(color, lineWidth: 2)
            .padding(-4)
            .opacity(on ? 1 : 0.25)
            .scaleEffect(on ? 1.06 : 0.98)
            .shadow(color: color.opacity(0.7), radius: on ? 8 : 2)
            .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { on = true } }
            .allowsHitTesting(false)
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
                levels.padding(.top, 30)
                Spacer(minLength: 16)
                Text(result)
                    .font(.system(size: 14).monospacedDigit())
                    .foregroundStyle(colors.ink.opacity(0.55))
                    .frame(minHeight: 20)
                Spacer(minLength: 16)
                Spacer(minLength: 16)
                OutlineButton(title: "Level \(game.chosen)", colors: colors) { game.start() }
                    .padding(.bottom, 64)
            }
        }
        .elasticDrag($drag)
        .sheet(isPresented: Binding(get: { game.askUnlock }, set: { game.askUnlock = $0 })) {
            UnlockSheet(colors: colors)
        }
        .onAppear {
            let cap = Unlock.shared.isUnlocked ? Maze.levels : Unlock.freeLevels
            let reached = max(1, min(cap, Settings.shared.mazeDeepest))
            if game.chosen > reached || game.lastRun == nil { game.chosen = reached }
            dropped = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55)) { dropped = true }
        }
    }

    /// The forty levels as four rows of squares: ones you've reached are filled (tap one to start
    /// there), with the stars you've won as three small marks; the one picked is outlined.
    private var levels: some View {
        let s = Settings.shared
        let reached = max(1, s.mazeDeepest)
        let grid = Array(repeating: GridItem(.fixed(22), spacing: 6), count: 10)
        let total = s.mazeStars.values.reduce(0, +)
        return VStack(spacing: 10) {
            LazyVGrid(columns: grid, spacing: 10) {
                ForEach(1...Maze.levels, id: \.self) { n in
                    let locked = n > Unlock.freeLevels && !Unlock.shared.isUnlocked
                    let open = n <= reached && !locked
                    let stars = s.mazeStars[String(n)] ?? 0
                    Button {
                        if locked { game.askUnlock = true; return }
                        guard open else { Haptics.tap(.soft, intensity: 0.3); return }
                        game.chosen = n
                        Haptics.tap(.light)
                    } label: {
                        VStack(spacing: 7) {
                            ZStack {
                                Rectangle().fill(open ? colors.accent.opacity(0.25 + 0.75 * Double(n) / Double(Maze.levels)) : colors.ink.opacity(0.06))
                                if game.chosen == n {
                                    Rectangle().strokeBorder(colors.ink, lineWidth: 1.5).padding(-3)
                                }
                                if locked {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(colors.ink.opacity(0.3))
                                } else {
                                    Text("\(n)")
                                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(open ? Color.white.opacity(0.9) : colors.ink.opacity(0.25))
                                }
                            }
                            .frame(width: 22, height: 22)
                            HStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { i in
                                    Rectangle().fill(i < stars ? colors.accent : colors.ink.opacity(0.12)).frame(width: 4, height: 2)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(locked ? "Level \(n), locked" : open ? "Level \(n), \(stars) stars" : "Level \(n), not reached yet")
                }
            }
            .frame(width: 10 * 22 + 9 * 6)
            if total > 0 {
                Text("\(total) of \(Maze.levels * 3) stars")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(colors.ink.opacity(0.45))
            }
        }
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 12) {
            rule(Rectangle().fill(colors.accent).frame(width: 12, height: 12), "You. Swipe to slide to the next turning")
            rule(glowMark, "Your light shines all around. Walls cast shadows")
            rule(Circle().fill(colors.accent).frame(width: 6, height: 6), "Drop dots to mark where you've been")
            rule(mapMark, "Pinch to see the map")
            rule(revealMark, "Find one to see the whole maze for 3 seconds")
            rule(goalMark, "Reach the star. Fewer slides, more stars")
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

    private var revealMark: some View {
        ZStack {
            Rectangle().strokeBorder(colors.accent, lineWidth: 1.5)
            Rectangle().fill(colors.accent).padding(4)
        }
        .frame(width: 13, height: 13)
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
            return "Out of all \(Maze.levels) levels · \(formatTime(r.time))"
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
