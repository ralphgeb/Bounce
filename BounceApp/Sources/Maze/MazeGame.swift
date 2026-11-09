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
    /// The level picked on the landing page (any level you've reached).
    var chosen = 1
    /// Set when a run reaches a locked level: the landing page then offers Unlock everything.
    var askUnlock = false
    /// Playing the tutorial's own small maze (the first time only).
    private(set) var inTutorial = false
    /// Slides made on this level, and the fewest that reach the star.
    private(set) var slides = 0
    private(set) var fewestSlides = 1
    /// Squares from you to the star (walking), and from the start.
    private(set) var stepsToStar = 0
    private(set) var startSteps = 1
    /// Stars won on the level just finished (1 to 3).
    private(set) var lastStars = 0
    private(set) var starsID = 0
    @ObservationIgnored private var walk: [Int] = []

    /// The count of squares to the star shows until you're within a fifth of the way: then you're
    /// close, and it's up to you (and your dots).
    var showsDistance: Bool { Double(stepsToStar) > Double(startSteps) * 0.2 }

    /// The time for three stars: two seconds a slide, plus fifteen seconds.
    var parTime: Double { Double(fewestSlides) * 2 + 15 }
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
    /// Map squares hidden in the maze: step on one and the whole maze, star included, shows for 2 seconds.
    @ObservationIgnored private(set) var reveals = Set<Int>()
    @ObservationIgnored private(set) var revealLeft: Double = 0
    let revealTime: Double = 2
    /// Walls you have lit on this level: shown on the map.
    @ObservationIgnored private(set) var seen = Set<Int>()
    /// 0 = normal view, 1 = the whole map. Eases towards mapTarget.
    @ObservationIgnored private(set) var map: Double = 0
    @ObservationIgnored var mapTarget: Double = 0
    @ObservationIgnored private var pinchedOut = false
    /// Tutorial: where to drop (or pick up) the dot, and how many slides away from it you've gone.
    @ObservationIgnored private var anchor: (x: Int, y: Int)?
    @ObservationIgnored private var awayMoves = 0
    /// A fade to the background and back (0...1), when the tutorial brings you back.
    @ObservationIgnored private(set) var blink: Double = 0
    @ObservationIgnored private var blinkTime: Double?
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
        level = max(1, min(Unlock.shared.isUnlocked ? Maze.levels : Unlock.freeLevels, chosen))
        totalTime = 0
        newRecord = false
        // 10 dots on level 1, and the 3 a level you'd have earned getting this far.
        dotsLeft = 3 * (level - 1)
        // The first time, a small tutorial maze comes before the real level.
        inTutorial = !Coach.seen("maze")
        if inTutorial { loadTutorial() } else { load(level) }
        phase = .playing
        ticker.start()
        if !inTutorial { show("Level \(level)") }
        coach.begin("maze", steps: [
            .init(text: "Swipe left.\nYou slide until a wall or a turning.", waitFor: .swipeLeft, gesture: .swipeLeft),
            .init(text: "Now swipe right.", waitFor: .swipeRight, gesture: .swipeRight),
            .init(text: "Tap to drop a dot here,\nso you know you've been here.", waitFor: .dropDot, gesture: .tap),
            .init(text: "Swipe left to move away,\nthen right to come back.\nTap to pick the dot up.", waitFor: .pickDot),
            .init(text: "Pinch to zoom out and see the map.\nLet go to come back.", waitFor: .hold, gesture: .pinch),
            .init(text: "Top right: the counter to the star.\nIt counts the squares left to walk,\nand switches off once you're close.",
                  waitFor: .tapToContinue, inline: true, pointer: .counter),
            .init(text: "Swipe up, then right,\nto reach the star.", waitFor: .goal),
            .init(text: "That's the game.\nFind the star in every level.\nFewer slides win more stars.\nThere are 40 levels.", waitFor: .tapToContinue, picture: .mazeGlow),
        ], onFinish: { [weak self] in self?.endTutorial() })
    }

    /// The tutorial's own maze: a corridor, a turn up and the star. Three dots to practise with.
    private func loadTutorial() {
        maze = Maze.tutorial()
        resetBoard()
        reveals = []
        dotsLeft = 0
        giveDots(3)
    }

    /// Tutorial done (or skipped): on to the real level.
    private func endTutorial() {
        guard inTutorial else { return }
        inTutorial = false
        dotsLeft = 3 * (level - 1)
        load(level)
        phase = .playing
        show("Level \(level)")
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
        resetBoard()
        placeReveals(l)
        // 10 dots on level 1; each new level adds 3 to what you have left.
        giveDots(l == 1 ? firstDots : dotsPerLevel)
    }

    private func resetBoard() {
        walk = maze.walkDistances()
        fewestSlides = max(1, fewestSlidesToStar())
        slides = 0
        startSteps = max(1, walk[maze.start.y * maze.width + maze.start.x])
        stepsToStar = startSteps
        tile = maze.start
        pos = center(tile)
        target = nil; moving = nil; queued = nil
        facing = -.pi / 2; facingTarget = facing
        dots = []
        seen = []
        revealLeft = 0
        map = 0; mapTarget = 0
        anchor = nil; awayMoves = 0
        levelTime = 0
        relight()
        frame &+= 1
    }

    private func center(_ t: (x: Int, y: Int)) -> CGPoint { CGPoint(x: Double(t.x) + 0.5, y: Double(t.y) + 0.5) }

    // MARK: Dots

    /// One map square on levels 1 to 4, then one more every four levels (at most 5), on floor
    /// tiles away from the start and the way out. The same for everyone.
    private func placeReveals(_ l: Int) {
        reveals = []
        var rng = SeededRandom(seed: UInt64(l) &* 92_821 &+ 3)
        let want = min(5, 1 + (l - 1) / 4)
        var tries = 0
        while reveals.count < want && tries < 2000 {
            tries += 1
            let x = 1 + 2 * Int(rng.next() % UInt64((maze.width - 1) / 2))
            let y = 1 + 2 * Int(rng.next() % UInt64((maze.height - 1) / 2))
            guard !maze.isWall(x, y) else { continue }
            let fromStart = abs(x - maze.start.x) + abs(y - maze.start.y)
            let fromGoal = abs(x - maze.goal.x) + abs(y - maze.goal.y)
            guard fromStart > 10, fromGoal > 8 else { continue }
            reveals.insert(Maze.key(x, y))
        }
    }

    private func giveDots(_ n: Int) {
        Sound.shared.play("twinkle", volume: 0.8)
        dotsLeft += n
        dotGain = n
        dotGainID += 1
        dotGainAge = 0
    }

    /// Pinch: zoom out towards the map while the fingers stay down.
    func pinch(_ amount: Double) {
        guard phase == .playing else { return }
        mapTarget = max(0, min(1, amount))
        if mapTarget > 0.5 && !pinchedOut {
            pinchedOut = true
            Haptics.tap(.soft, intensity: 0.5)
            Sound.shared.play("whoosh", volume: 0.5)
        }
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
            Sound.shared.play("plop")
            coach.did(.pickDot)
        } else if dotsLeft > 0 {
            dots.insert(k); dotsLeft -= 1
            Haptics.tap(.rigid, intensity: 0.6)
            Sound.shared.play("plip")
            coach.did(.dropDot)
            // The next step is to pick this dot up: stay near it.
            if coach.current?.waitFor == .pickDot { anchor = tile; awayMoves = 0 }
        } else {
            show("No dots left")
            Haptics.notify(.warning)
            Sound.shared.play("bump", volume: 0.6)
        }
        frame &+= 1
    }

    // MARK: Moving

    func swipe(_ d: Dir) {
        guard phase == .playing, blinkTime == nil else { return }
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
            Sound.shared.play("bump", volume: 0.5, gap: 0.12)
            return
        }
        target = (x, y)
        moving = d
        slides += 1
        // The swish of the slide: a little longer and louder for long ones.
        Sound.shared.play(steps > 3 ? "swish_long" : "swish", volume: Float(min(1, 0.45 + Double(steps) * 0.08)), gap: 0.05)
    }

    private func arrive() {
        guard let t = target else { return }
        tile = t
        pos = center(t)
        target = nil
        moving = nil
        stepsToStar = max(0, walk[t.y * maze.width + t.x])
        Haptics.tap(.light, intensity: 0.45)
        if t.x == maze.goal.x && t.y == maze.goal.y { cleared(); return }
        // Tutorial: while it asks you to drop or pick up a dot, you can't wander more than two
        // slides away; the screen fades and you're back where you were.
        if let w = coach.current?.waitFor, w == .dropDot || w == .pickDot {
            if let a = anchor {
                if a.x != t.x || a.y != t.y {
                    awayMoves += 1
                    if awayMoves >= 2 { queued = nil; blinkTime = 0; Sound.shared.play("swish_soft"); return }
                } else {
                    awayMoves = 0
                }
            } else {
                anchor = t; awayMoves = 0
            }
        } else {
            anchor = nil
        }
        if let q = queued { queued = nil; go(q) }
    }

    private func cleared() {
        // The tutorial's star: well done; the last card, then the real level.
        if inTutorial {
            flash = 1
            Haptics.notify(.success)
            Sound.shared.play("win")
            coach.did(.goal)
            return
        }
        phase = .cleared
        flash = 1
        Haptics.notify(.success)
        Sound.shared.play("win")
        let s = Settings.shared
        let key = String(level)
        // Stars, with some leeway: three for up to half as many slides again as the fewest (plus two)
        // within the time; two for up to about two and a half times the fewest; one otherwise.
        var stars = 1
        if slides <= Int((Double(fewestSlides) * 2.5).rounded(.up)) + 3 { stars = 2 }
        if slides <= Int((Double(fewestSlides) * 1.5).rounded(.up)) + 2 && levelTime <= parTime { stars = 3 }
        lastStars = stars
        // Then one bell for each star, rising.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.7))
            Sound.shared.bells(Array([6, 8, 10].prefix(stars)), every: 0.22)
        }
        starsID += 1
        if stars > (s.mazeStars[key] ?? 0) { s.mazeStars[key] = stars }
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
        // Levels past the free ones need Unlock everything: end the run and offer it.
        if level + 1 > Unlock.freeLevels && !Unlock.shared.isUnlocked {
            show("Level \(level + 1) is locked")
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, self.phase == .cleared else { return }
                self.phase = .playing
                self.home()
                self.askUnlock = true
            }
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard let self, self.phase == .cleared else { return }
            self.level += 1
            self.load(self.level)
            self.phase = .playing
            self.show("Level \(self.level)")
        }
    }

    /// The fewest slides from the start to the star (each slide goes to the next wall or turning).
    private func fewestSlidesToStar() -> Int {
        let w = maze.width
        var seen = [Int: Int]()
        var queue = [(maze.start.x, maze.start.y)], head = 0
        seen[maze.start.y * w + maze.start.x] = 0
        while head < queue.count {
            let (x0, y0) = queue[head]; head += 1
            let d = seen[y0 * w + x0]!
            if x0 == maze.goal.x && y0 == maze.goal.y { return d }
            for dir in Dir.allCases {
                var x = x0, y = y0, n = 0
                while !maze.isWall(x + dir.dx, y + dir.dy) {
                    x += dir.dx; y += dir.dy; n += 1
                    if x == maze.goal.x && y == maze.goal.y { break }
                    if !maze.isWall(x + dir.dy, y + dir.dx) || !maze.isWall(x - dir.dy, y - dir.dx) { break }
                }
                guard n > 0, seen[y * w + x] == nil else { continue }
                seen[y * w + x] = d + 1
                queue.append((x, y))
            }
        }
        return 1
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

        // A map square under you: zoom out over the whole maze, every wall showing, for 3 seconds.
        let here = Maze.key(Int(floor(pos.x)), Int(floor(pos.y)))
        if reveals.contains(here) {
            reveals.remove(here)
            revealLeft = revealTime
            show("Map")
            Haptics.notify(.success)
            Sound.shared.play("reveal")
        }
        if revealLeft > 0 {
            revealLeft = max(0, revealLeft - dt)
            mapTarget = revealLeft > 0 ? 1 : (pinchedOut ? mapTarget : 0)
        }
        if let start = blinkTime {
            // Fade out, come back to the spot while it's dark, fade in.
            let b = start + dt
            if start < 0.32 && b >= 0.32, let a = anchor {
                tile = a
                pos = center(a)
                target = nil; moving = nil; queued = nil
                awayMoves = 0
            }
            blink = b < 0.32 ? b / 0.32 : max(0, 1 - (b - 0.32) / 0.4)
            if b > 0.72 { blinkTime = nil; blink = 0 } else { blinkTime = b }
        }
        dotGainAge += dt

        relight()
        frame &+= 1
    }

    private func relight() {
        range = baseRange * (1 + 0.025 * sin(totalTime * 1.7))
        var l: [Int: Double] = [:]
        var floors = Set<Int>()
        light = Lighting.cast(maze, from: pos, angle: 0, halfAngle: .pi, range: range, rays: 360, lit: &l, floors: &floors)
        Lighting.fillCorners(maze, lit: &l, floors: floors)
        // How bright each lit wall is depends only on how far it is from you, so it stays steady
        // while the light breathes and the rays sweep; only walls the light actually reaches show.
        for k in l.keys {
            let x = Double(k % 20_000 - 16) + 0.5, y = Double(k / 20_000 - 16) + 0.5
            let d = max(0, hypot(x - Double(pos.x), y - Double(pos.y)) - 0.5)
            l[k] = max(0.04, 1 - d / baseRange)
        }
        lit = l
        seen.formUnion(l.keys)
    }
}
