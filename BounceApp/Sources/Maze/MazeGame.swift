import SwiftUI

/// Maze: you are a square in the dark with a cone of light in front of you. Swipe to slide;
/// you stop at walls and at every turning. Find the glowing way out to go one level deeper.
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

    // The board, in tile units. The canvas reads these every frame.
    @ObservationIgnored private(set) var maze = Maze.generate(level: 1)
    @ObservationIgnored private(set) var pos = CGPoint(x: 1.5, y: 1.5)      // the player's centre
    @ObservationIgnored private(set) var facing: Double = -.pi / 2          // where the light points
    @ObservationIgnored private(set) var cone: [CGPoint] = []
    @ObservationIgnored private(set) var halo: [CGPoint] = []
    @ObservationIgnored private(set) var lit: [Int: Double] = [:]
    @ObservationIgnored private(set) var seen = Set<Int>()
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

    let coneHalfAngle = 0.62          // about 70° wide
    let coneRange = 7.5               // tiles
    let haloRange = 1.6
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
        load(level)
        phase = .playing
        ticker.start()
        show("Level 1")
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
        seen = []
        levelTime = 0
        relight()
        frame &+= 1
    }

    private func center(_ t: (x: Int, y: Int)) -> CGPoint { CGPoint(x: Double(t.x) + 0.5, y: Double(t.y) + 0.5) }

    // MARK: Moving

    func swipe(_ d: Dir) {
        guard phase == .playing else { return }
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
        if level + 1 > s.mazeDeepest { s.mazeDeepest = level + 1; newRecord = true }
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

        relight()
        frame &+= 1
    }

    private func relight() {
        var l: [Int: Double] = [:]
        cone = Lighting.cast(maze, from: pos, angle: facing, halfAngle: coneHalfAngle, range: coneRange, rays: 150, lit: &l)
        halo = Lighting.cast(maze, from: pos, angle: 0, halfAngle: .pi, range: haloRange, rays: 56, lit: &l)
        lit = l
        seen.formUnion(l.keys)
    }
}
