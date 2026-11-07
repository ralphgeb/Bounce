import SwiftUI

/// Maze: you are a square in pitch black, giving off light all around you. Walls catch the light and
/// throw shadows, and that is all you see. Swipe to slide; you stop at walls and at every turning.
/// Tap to drop a dot so you know where you've been (10 to start, 3 more each level). Pinch to zoom
/// out and see where your dots are compared to you. Find the glowing way out to go deeper.
@MainActor
@Observable
final class MazeGame {
    enum Phase { case ready, playing, paused, cleared }

    enum Dir: CaseIterable {
        case up, down, left, right
        var dx: Int { self == .left ? -1 : self == .right ? 1 : 0 }
        var dy: Int { self == .up ? -1 : self == .down ? 1 : 0 }
        var angle: Double {
            switch self {
            case .right: return 0
            case .down: return .pi / 2
            case .left: return .pi
            case .up: return -.pi / 2
            }
        }
    }

    private(set) var phase: Phase = .ready
    private(set) var level = 1
    private(set) var levelTime: Double = 0
    private(set) var totalTime: Double = 0
    private(set) var frame = 0
    private(set) var toast: String?
    private(set) var toastID = 0
    /// After a run: the level you got to and how long it took (for the landing page).
    private(set) var lastRun: (level: Int, time: Double)?
    private(set) var newRecord = false
    private(set) var dotsLeft = 10
    /// The last dots you were given, and when (for the little animation).
    private(set) var dotGain = 0
    private(set) var dotGainID = 0
    let firstDots = 10
    let dotsPerLevel = 3
    /// The first-time tutorial.
    let coach = Coach()

    // The board, in tile units. The canvas reads these every frame.
    @ObservationIgnored private(set) var maze = Maze.generate(level: 1)
    @ObservationIgnored private(set) var pos = CGPoint(x: 1.5, y: 1.5)      // the player's centre
    @ObservationIgnored private(set) var facing: Double = -.pi / 2          // where the light points
    @ObservationIgnored private(set) var light: [CGPoint] = []
    @ObservationIgnored private(set) var lit: [Int: Double] = [:]
    @ObservationIgnored private(set) var dots = Set<Int>()
    /// Walls you have lit on this level: shown on the map.
    @ObservationIgnored private(set) var seen = Set<Int>()
    /// 0 = normal view, 1 = the whole map. Eases towards mapTarget.
    @ObservationIgnored private(set) var map: Double = 0
    @ObservationIgnored var mapTarget: Double = 0
    @ObservationIgnored private var pinchedOut = false
    @ObservationIgnored private var mapDone = false
    /// Seconds since the dots were given (for the ring of new dots around you).
    @ObservationIgnored private(set) var dotGainAge: Double = 9
    @ObservationIgnored private(set) var range: Double = 5
    @ObservationIgnored private(set) var flash: Double = 0
    @ObservationIgnored private(set) var bump: (dir: Dir, amount: Double)?
    @ObservationIgnored private(set) var squash: Double = 0                  // a little stretch while sliding

    @ObservationIgnored private var tile = (x: 1, y: 1)
    @ObservationIgnored private var target: (x: Int, y: Int)?
    @ObservationIgnored private(set) var moving: Dir?
    @ObservationIgnored private var queued: Dir?
    @ObservationIgnored private var facingTarget: Double = -.pi / 2
    private let ticker = FrameTicker()
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    /// How far the light reaches, in tiles. It breathes a little.
    let baseRange = 5.0
    private let speed = 13.0          // tiles a second

    init() {
        ticker.onTick = { [weak self] dt in
            MainActor.assumeIsolated { self?.tick(dt) }
        }
    }

    // MARK: Phases

    func start() {
        level = 1
        totalTime = 0
        newRecord = false
        dotsLeft = 0
        load(level)
        phase = .playing
        ticker.start()
        show("Level 1")
        coach.begin("maze", steps: [
            .init(text: "Swipe left.\nYou slide until a wall or a turning.", waitFor: .swipeLeft, gesture: .swipeLeft),
            .init(text: "Now swipe right.", waitFor: .swipeRight, gesture: .swipeRight),
            .init(text: "Tap to drop a dot here,\nso you know you've been here.", waitFor: .dropDot, gesture: .tap),
            .init(text: "Tap again to pick it up.\nDots are few: reuse them.", waitFor: .pickDot, gesture: .tap),
            .init(text: "Pinch to zoom out.\nYou'll see your dots and where you are.\nLet go to come back.", waitFor: .hold, gesture: .pinch),
            .init(text: "Find the glowing star\nto go one level deeper.\nThere are 20 levels.", waitFor: .tapToContinue, picture: .mazeGlow),
        ])
    }

    func pause() { if phase == .playing { phase = .paused } }
    func resume() { if phase == .paused { phase = .playing } }

    /// End the run and go back to the landing page.
    func home() {
        if phase != .ready { lastRun = (level, totalTime) }
        phase = .ready
        ticker.stop()
    }

    private func load(_ l: Int) {
        maze = Maze.generate(level: l)
        tile = maze.start
        pos = center(tile)
        target = nil; moving = nil; queued = nil
        facing = -.pi / 2; facingTarget = facing
        dots = []
        seen = []
        map = 0; mapTarget = 0
        // 10 dots on level 1; each new level adds 3 to what you have left.
        giveDots(l == 1 ? firstDots : dotsPerLevel)
        levelTime = 0
        relight()
        frame &+= 1
    }

    private func center(_ t: (x: Int, y: Int)) -> CGPoint { CGPoint(x: Double(t.x) + 0.5, y: Double(t.y) + 0.5) }

    // MARK: Dots

    private func giveDots(_ n: Int) {
        dotsLeft += n
        dotGain = n
        dotGainID += 1
        dotGainAge = 0
    }

    /// Pinch: zoom out towards the map while the fingers stay down.
    func pinch(_ amount: Double) {
        guard phase == .playing else { return }
        mapTarget = max(0, min(1, amount))
        if mapTarget > 0.5 && !pinchedOut { pinchedOut = true; Haptics.tap(.soft, intensity: 0.5) }
    }

    /// Fingers lifted: zoom back. The tutorial's map step finishes once you're back where you were.
    func endPinch() {
        mapTarget = 0
        if pinchedOut { mapDone = true }
        pinchedOut = false
    }

    /// Tap: drop a dot where you stand, or pick one up if there's one here.
    func tap() {
        guard phase == .playing, target == nil else { return }
        let k = Maze.key(tile.x, tile.y)
        if dots.contains(k) {
            dots.remove(k); dotsLeft += 1
            Haptics.tap(.soft, intensity: 0.6)
            coach.did(.pickDot)
        } else if dotsLeft > 0 {
            dots.insert(k); dotsLeft -= 1
            Haptics.tap(.rigid, intensity: 0.6)
            coach.did(.dropDot)
        } else {
            show("No dots left")
            Haptics.notify(.warning)
        }
        frame &+= 1
    }

    // MARK: Moving

    func swipe(_ d: Dir) {
        guard phase == .playing else { return }
        if d == .left { coach.did(.swipeLeft) }
        if d == .right { coach.did(.swipeRight) }
        if target != nil { queued = d; return }
        go(d)
    }

    private func go(_ d: Dir) {
        // The light turns first, the short way round.
        let diff = remainder(d.angle - facingTarget, 2 * .pi)
        facingTarget += diff

        // Slide until a wall, a turning, or the way out.
        var x = tile.x, y = tile.y, steps = 0
        while !maze.isWall(x + d.dx, y + d.dy) {
            x += d.dx; y += d.dy; steps += 1
            if x == maze.goal.x && y == maze.goal.y { break }
            let sideOpen = !maze.isWall(x + d.dy, y + d.dx) || !maze.isWall(x - d.dy, y - d.dx)
            if sideOpen { break }
        }
        guard steps > 0 else {
            bump = (d, 1)
            Haptics.tap(.soft, intensity: 0.35)
            return
        }
        target = (x, y)
        moving = d
    }

    private func arrive() {
        guard let t = target else { return }
        tile = t
        pos = center(t)
        target = nil
        moving = nil
        Haptics.tap(.light, intensity: 0.45)
        if t.x == maze.goal.x && t.y == maze.goal.y { cleared(); return }
        if let q = queued { queued = nil; go(q) }
    }

    private func cleared() {
        phase = .cleared
        flash = 1
        Haptics.notify(.success)
        let s = Settings.shared
        let key = String(level)
        if levelTime < (s.mazeTimes[key] ?? .infinity) { s.mazeTimes[key] = levelTime }
        let last = level >= Maze.levels
        let reached = last ? Maze.levels : level + 1
        if reached > s.mazeDeepest || (last && !s.mazeFinished) {
            s.mazeDeepest = reached; newRecord = true
        }
        if last {
            // The way out of level 20: the whole maze is done.
            s.mazeFinished = true
            show("You made it out")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, self.phase == .cleared else { return }
                self.phase = .playing
                self.home()
            }
            return
        }
        show("Level \(level + 1)")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.1))
            guard let self, self.phase == .cleared else { return }
            self.level += 1
            self.load(self.level)
            self.phase = .playing
        }
    }

    private func show(_ text: String) {
        toast = text; toastID += 1
        let id = toastID
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, self.toastID == id else { return }
            self.toast = nil
        }
    }

    // MARK: Loop

    private func tick(_ dt: Double) {
        guard phase == .playing || phase == .cleared else { return }
        if phase == .playing {
            levelTime += dt
            totalTime += dt
        }

        // Turn the light smoothly.
        facing += (facingTarget - facing) * min(1, dt * 14)

        if let t = target, let d = moving {
            let goal = center(t)
            let step = speed * dt
            let left = abs(Double(goal.x - pos.x)) + abs(Double(goal.y - pos.y))
            if step >= left {
                arrive()
            } else {
                pos.x += CGFloat(Double(d.dx) * step)
                pos.y += CGFloat(Double(d.dy) * step)
            }
            squash = min(1, squash + dt * 8)
        } else {
            squash = max(0, squash - dt * 10)
        }

        if var b = bump {
            b.amount -= dt * 6
            bump = b.amount > 0 ? b : nil
        }
        if flash > 0 { flash = max(0, flash - dt * 1.4) }
        map += (mapTarget - map) * min(1, dt * 9)
        if abs(map - mapTarget) < 0.002 { map = mapTarget }
        if mapDone && map < 0.02 { mapDone = false; coach.did(.hold) }
        dotGainAge += dt

        relight()
        frame &+= 1
    }

    private func relight() {
        range = baseRange * (1 + 0.025 * sin(totalTime * 1.7))
        var l: [Int: Double] = [:]
        light = Lighting.cast(maze, from: pos, angle: 0, halfAngle: .pi, range: range, rays: 360, lit: &l)
        Lighting.fillCorners(maze, lit: &l)
        lit = l
        seen.formUnion(l.keys)
    }
}
