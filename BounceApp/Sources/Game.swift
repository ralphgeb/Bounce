import SwiftUI
import QuartzCore

/// One square in the wall. Plain squares take 1 to 3 hits (darker is tougher); the special ones break in one.
struct Block {
    enum Kind {
        case plain
        case split      // accent square: the ball splits in three
        case blaster    // accent outline: the paddle shoots for three seconds
        case row        // chamfered, line across: clears its row
        case column     // chamfered, line down: clears its column
        case bomb       // big circle: clears every square on the screen
    }

    var rect: CGRect
    var hp: Int
    var max: Int
    var kind: Kind = .plain
    var hit: Double = 0      // flash when struck, fades out
    var age: Double = 0      // fades in when the row arrives
}

struct Ball {
    var p: CGPoint
    var v: CGVector
    var r: CGFloat = 6
    var stuck = false
    var trail: [CGPoint] = []
}

struct Particle {
    var p: CGPoint
    var v: CGVector
    var life: Double
    var size: CGFloat
}

/// The game: a paddle, one or more balls, and an endless wall of squares drifting down.
/// Runs on a display link; the view redraws whenever `frame` changes.
@MainActor
@Observable
final class Game {
    enum Phase { case ready, playing, paused, over }

    // What the screen shows around the game.
    private(set) var phase: Phase = .ready
    private(set) var score = 0
    private(set) var lives = 3
    private(set) var chain = 1
    private(set) var elapsed: Double = 0
    private(set) var frame = 0
    private(set) var freshLife = false
    private(set) var toast: String?
    private(set) var toastID = 0
    private(set) var newBest = false
    /// The first-time tutorial.
    let coach = Coach()
    @ObservationIgnored private var dragFrom: CGFloat?

    // The board, in points. Not observed: the canvas reads it every frame.
    @ObservationIgnored private(set) var size: CGSize = .zero
    @ObservationIgnored private(set) var top: CGFloat = 112
    @ObservationIgnored private(set) var paddleY: CGFloat = 0
    @ObservationIgnored private(set) var paddleX: CGFloat = 0
    @ObservationIgnored private(set) var paddleW: CGFloat = 92
    let paddleH: CGFloat = 10
    @ObservationIgnored private(set) var blocks: [Block] = []
    @ObservationIgnored private(set) var balls: [Ball] = []
    @ObservationIgnored private(set) var particles: [Particle] = []
    @ObservationIgnored private(set) var flash: Double = 0
    @ObservationIgnored private(set) var bullets: [CGPoint] = []
    /// Rows and columns just cleared, drawn as a fading accent band.
    @ObservationIgnored private(set) var sweeps: [(rect: CGRect, life: Double)] = []
    /// Seconds of shooting left (from a blaster square).
    @ObservationIgnored private(set) var shootLeft: Double = 0
    @ObservationIgnored private var shotClock: Double = 0
    @ObservationIgnored var targetX: CGFloat?
    let shootTime: Double = 3

    let cols = 9
    let gap: CGFloat = 5
    let side: CGFloat = 18
    @ObservationIgnored private var cell: CGFloat = 30
    @ObservationIgnored private var nextRowY: CGFloat = 0
    @ObservationIgnored private var run = 0
    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private var lastTime: CFTimeInterval = 0
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    var rowH: CGFloat { cell + gap }
    var dangerY: CGFloat { paddleY - 6 }

    // MARK: Layout

    /// Called with the screen size and the safe area (top for the score, bottom for the home bar).
    func layout(size: CGSize, safeTop: CGFloat, safeBottom: CGFloat) {
        guard size.width > 0, size.height > 0 else { return }
        let changed = size != self.size
        self.size = size
        top = safeTop + 78
        // High enough to leave room for a thumb under the paddle.
        paddleY = size.height - max(safeBottom, 16) - 118
        paddleW = max(64, size.width * 0.24)
        let newCell = (size.width - side * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)
        if changed && phase == .ready { cell = newCell; paddleX = size.width / 2 }
        cell = newCell
    }

    // MARK: Phases

    func start() {
        reset()
        phase = .playing
        startLoop()
        coach.begin("bounce", steps: [
            .init(text: "Slide anywhere\nto move the paddle", waitFor: .drag, gesture: .dragSideways, place: .low),
            .init(text: "Tap to send the ball", waitFor: .launch, gesture: .tap, place: .low),
            .init(text: "The wall moves down, slowly.\nBreak squares before it reaches\nthe line above your paddle.",
                  waitFor: .tapToContinue, picture: .wallDown),
            .init(text: "Accent squares are power-ups.\nThe landing page shows what each does.",
                  waitFor: .tapToContinue, picture: .bouncePowers),
        ])
        // With the tutorial on, the ball waits for its step.
        if !coach.active { launch() }
    }

    func pause() {
        guard phase == .playing else { return }
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        lastTime = 0
        phase = .playing
    }

    func home() {
        phase = .ready
        stopLoop()
    }

    private func reset() {
        elapsed = 0; score = 0; lives = 3; run = 0; freshLife = false; newBest = false
        particles = []; flash = 0; bullets = []; shootLeft = 0; sweeps = []
        paddleX = size.width / 2
        dragFrom = nil
        blocks = []
        // The two starting rows nearest the paddle are plain: power-ups start from the third row up.
        for i in 0..<4 { blocks += makeRow(y: top + CGFloat(i) * rowH, specials: i < 2) }
        nextRowY = top
        serve()
    }

    private func serve() {
        balls = [Ball(p: CGPoint(x: paddleX, y: paddleY - 13), v: .zero, stuck: true)]
        chain = 1
        run = 0
    }

    /// The first tap sends the ball off the paddle.
    func launch() {
        guard phase == .playing, var b = balls.first, b.stuck else { return }
        if coach.active && coach.current?.waitFor != .launch { return }
        coach.did(.launch)
        let a = (-90 + Double.random(in: -15...15)) * .pi / 180
        let sp = baseSpeed
        b.v = CGVector(dx: cos(a) * sp, dy: sin(a) * sp)
        b.stuck = false
        balls[0] = b
    }

    private var baseSpeed: Double { min(Double(size.height) * 0.46 + elapsed * 1.5, Double(size.height) * 0.82) }

    private func gameOver() {
        phase = .over
        let s = Settings.shared
        if score > s.best { s.best = score; newBest = score > 0 }
        if elapsed > s.longest { s.longest = elapsed }
        Haptics.notify(.error)
        stopLoop()
        frame &+= 1
    }

    private func show(_ text: String) {
        toast = text; toastID += 1
        let id = toastID
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard let self, self.toastID == id else { return }
            self.toast = nil
        }
    }

    // MARK: The wall

    private func makeRow(y: CGFloat, specials: Bool = true) -> [Block] {
        // Each row leaves 1 to 3 gaps, and blocks get tougher the longer you last.
        let level = Double(Int(elapsed / 25))
        let holes = Int.random(in: 1...3)
        var skip = Set<Int>()
        while skip.count < holes { skip.insert(Int.random(in: 0..<cols)) }
        var row: [Block] = []
        for c in 0..<cols where !skip.contains(c) {
            let roll = Double.random(in: 0..<1)
            var hp = roll < 0.12 + level * 0.06 ? 3 : roll < 0.38 + level * 0.08 ? 2 : 1
            // Special squares, at random, roughly: a row or column clearer every 20 squares, a split
            // every 50, a blaster every 100 and a screen-clearing circle every 150.
            let k = specials ? Self.randomKind() : .plain
            if k != .plain { hp = 1 }
            let x = side + CGFloat(c) * (cell + gap)
            row.append(Block(rect: CGRect(x: x, y: y, width: cell, height: cell), hp: hp, max: hp, kind: k))
        }
        return row
    }

    // MARK: Loop

    private func startLoop() {
        guard link == nil else { return }
        lastTime = 0
        let proxy = LinkProxy(self)
        let l = CADisplayLink(target: proxy, selector: #selector(LinkProxy.tick(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func stopLoop() {
        link?.invalidate()
        link = nil
    }

    fileprivate func tick(_ time: CFTimeInterval) {
        let dt = lastTime == 0 ? 1.0 / 60 : min(1.0 / 30, time - lastTime)
        lastTime = time
        guard phase == .playing else { return }
        // While a tutorial card is up, the game waits.
        if coach.current?.waitFor != .tapToContinue { step(dt) }
        fade(dt)
        frame &+= 1
    }

    private func fade(_ dt: Double) {
        for i in blocks.indices {
            blocks[i].age = min(1, blocks[i].age + dt * 2.5)
            if blocks[i].hit > 0 { blocks[i].hit = max(0, blocks[i].hit - dt * 5) }
        }
        var i = particles.count - 1
        while i >= 0 {
            particles[i].life -= dt * 2
            if particles[i].life <= 0 { particles.remove(at: i) } else {
                particles[i].p.x += particles[i].v.dx * dt
                particles[i].p.y += particles[i].v.dy * dt
                particles[i].v.dy += 300 * dt
            }
            i -= 1
        }
        if flash > 0 { flash = max(0, flash - dt * 2.5) }
        for j in sweeps.indices.reversed() {
            sweeps[j].life -= dt * 3
            if sweeps[j].life <= 0 { sweeps.remove(at: j) }
        }
    }

    private func burst(_ b: Block, count: Int = 10) {
        for _ in 0..<count {
            particles.append(Particle(
                p: CGPoint(x: b.rect.minX + .random(in: 0...b.rect.width), y: b.rect.minY + .random(in: 0...b.rect.height)),
                v: CGVector(dx: .random(in: -80...80), dy: .random(in: -120...40)),
                life: 1, size: .random(in: 2...5)))
        }
    }

    private func loseLife() -> Bool {
        lives -= 1; freshLife = false
        Haptics.notify(.warning)
        if lives <= 0 { gameOver(); return true }
        show(lives == 1 ? "Last life" : "\(lives) lives left")
        return false
    }

    private func step(_ dt: Double) {
        elapsed += dt
        let w = size.width
        let half = paddleW / 2

        // Paddle follows the finger, smoothly.
        if let tx = targetX {
            paddleX += (tx - paddleX) * CGFloat(min(1, dt * 22))
            if dragFrom == nil { dragFrom = tx }
            if let f = dragFrom, abs(tx - f) > 40 { coach.did(.drag) }
        }
        paddleX = max(side / 2 + half, min(w - side / 2 - half, paddleX))

        // While the tutorial is on, the wall waits.
        if !coach.active {
            // The wall drifts down, a little faster over time: endless.
            let fall = (3.2 + elapsed * 0.07) * Double(size.height / 760)
            let dy = CGFloat(fall * dt)
            for i in blocks.indices { blocks[i].rect.origin.y += dy }
            nextRowY += dy
            // A new row slides in at the top each time the top row has moved down by one row.
            while nextRowY >= top + rowH {
                nextRowY -= rowH
                blocks += makeRow(y: nextRowY)
            }
        }

        // A block reaching the line costs a life and knocks the bottom three rows away.
        if blocks.contains(where: { $0.rect.maxY >= dangerY }) {
            if loseLife() { return }
            let cut = dangerY - rowH * 3
            for b in blocks where b.rect.maxY > cut { burst(b) }
            blocks.removeAll { $0.rect.maxY > cut }
            flash = 1
        }

        // Blaster: two shots from the ends of the paddle every 0.16 s.
        if shootLeft > 0 {
            shootLeft = max(0, shootLeft - dt)
            shotClock -= dt
            if shotClock <= 0 {
                shotClock = 0.16
                bullets.append(CGPoint(x: paddleX - half + 3, y: paddleY - paddleH / 2))
                bullets.append(CGPoint(x: paddleX + half - 3, y: paddleY - paddleH / 2))
            }
        }
        let shotSpeed = size.height * 1.3 * CGFloat(dt)
        var k = bullets.count - 1
        while k >= 0 {
            bullets[k].y -= shotSpeed
            let pt = bullets[k]
            if let i = blocks.lastIndex(where: { $0.rect.insetBy(dx: -1, dy: 0).contains(pt) }) {
                bullets.remove(at: k)
                hit(i, ball: nil)
            } else if pt.y < top - 30 {
                bullets.remove(at: k)
            }
            k -= 1
        }

        // Balls
        if balls[0].stuck {
            balls[0].p = CGPoint(x: paddleX, y: paddleY - 13)
            return
        }
        let sub = 4
        let sdt = CGFloat(dt) / CGFloat(sub)
        var bi = balls.count - 1
        while bi >= 0 {
            var ball = balls[bi]
            var gone = false
            for _ in 0..<sub {
                ball.p.x += ball.v.dx * sdt
                ball.p.y += ball.v.dy * sdt
                if ball.p.x < ball.r { ball.p.x = ball.r; ball.v.dx = abs(ball.v.dx) }
                if ball.p.x > w - ball.r { ball.p.x = w - ball.r; ball.v.dx = -abs(ball.v.dx) }
                let ceiling = top - 30 + ball.r
                if ball.p.y < ceiling && ball.v.dy < 0 { ball.p.y = ceiling; ball.v.dy = abs(ball.v.dy) }

                // Paddle: where it lands sets the angle, as in Pong. Touching it ends the chain.
                if ball.v.dy > 0, ball.p.y + ball.r >= paddleY - paddleH / 2, ball.p.y < paddleY + paddleH,
                   abs(ball.p.x - paddleX) <= half + ball.r {
                    let t = max(-1, min(1, (ball.p.x - paddleX) / half))
                    let ang = (-90 + Double(t) * 60) * .pi / 180
                    let sp = max(baseSpeed, Double(hypot(ball.v.dx, ball.v.dy)))
                    ball.v = CGVector(dx: cos(ang) * sp, dy: sin(ang) * sp)
                    ball.p.y = paddleY - paddleH / 2 - ball.r
                    chain = 1
                    run = 0
                    Haptics.tap(.light, intensity: 0.6)
                }

                // Blocks
                var i = blocks.count - 1
                while i >= 0 {
                    let r = blocks[i].rect
                    let cx = max(r.minX, min(ball.p.x, r.maxX)), cy = max(r.minY, min(ball.p.y, r.maxY))
                    let dx = ball.p.x - cx, dyy = ball.p.y - cy
                    if dx * dx + dyy * dyy <= ball.r * ball.r {
                        let ox = min(ball.p.x + ball.r - r.minX, r.maxX - (ball.p.x - ball.r))
                        let oy = min(ball.p.y + ball.r - r.minY, r.maxY - (ball.p.y - ball.r))
                        if ox < oy {
                            ball.v.dx *= -1; ball.p.x += ball.v.dx > 0 ? ox : -ox
                        } else {
                            ball.v.dy *= -1; ball.p.y += ball.v.dy > 0 ? oy : -oy
                        }
                        hit(i, ball: ball)
                        break
                    }
                    i -= 1
                }
                if ball.p.y - ball.r > size.height { gone = true; break }
            }
            if gone {
                balls.remove(at: bi)
                // Extra balls just disappear; losing the last one costs a life.
                if balls.isEmpty {
                    if loseLife() { return }
                    serve()
                    return
                }
            } else {
                ball.trail.append(ball.p)
                if ball.trail.count > 8 { ball.trail.removeFirst() }
                if bi < balls.count { balls[bi] = ball }
            }
            bi -= 1
        }
    }

    /// A ball or a shot hits block i. Only balls grow the score multiplier and the run of 20.
    private func hit(_ i: Int, ball: Ball?) {
        blocks[i].hp -= 1
        blocks[i].hit = 1
        guard blocks[i].hp <= 0 else {
            Haptics.tap(.soft, intensity: 0.4)
            return
        }
        let b = blocks.remove(at: i)
        burst(b, count: 10)
        score += b.max * chain
        Haptics.tap(.rigid, intensity: 0.5)
        if ball != nil {
            chain = min(chain + 1, 9)
            run += 1
            // Twenty in a row without the paddle: an extra life (at most 5).
            if run % 20 == 0 {
                if lives < 5 { lives += 1; freshLife = true; show("Extra life") }
                else { score += 50; show("+50") }
                Haptics.notify(.success)
            }
        }
        trigger(b, ball: ball)
    }

    /// What a special square does when it breaks. Specials caught in a clear go off too.
    private func trigger(_ first: Block, ball: Ball?) {
        var queue = [first]
        while let b = queue.popLast() {
            var cleared: [Block] = []
            switch b.kind {
            case .plain:
                break
            case .split:
                if let src = ball ?? balls.first(where: { !$0.stuck }) { split(from: src) }
            case .blaster:
                shootLeft = shootTime
                shotClock = 0
                show("Blaster")
                Haptics.notify(.success)
            case .row:
                let band = CGRect(x: 0, y: b.rect.minY, width: size.width, height: b.rect.height)
                cleared = take { abs($0.rect.midY - b.rect.midY) < cell / 2 }
                sweeps.append((band, 1))
                Haptics.tap(.heavy)
            case .column:
                let band = CGRect(x: b.rect.minX, y: top - 30, width: b.rect.width, height: dangerY - top + 30)
                cleared = take { abs($0.rect.midX - b.rect.midX) < cell / 2 }
                sweeps.append((band, 1))
                Haptics.tap(.heavy)
            case .bomb:
                cleared = take { _ in true }
                flash = 1
                show("Clear")
                Haptics.notify(.success)
            }
            for c in cleared {
                score += c.max * chain
                burst(c, count: cleared.count > 20 ? 3 : 6)
                if c.kind != .plain { queue.append(c) }
            }
        }
    }

    /// Removes and returns every block that matches.
    private func take(_ match: (Block) -> Bool) -> [Block] {
        let out = blocks.filter(match)
        blocks.removeAll(where: match)
        return out
    }

    private static let bounceOdds: [(Block.Kind, Double)] = [
        (.split, 0.02), (.row, 0.025), (.column, 0.025), (.blaster, 0.01), (.bomb, 1.0 / 150),
    ]
    private static func randomKind() -> Block.Kind {
        let r = Double.random(in: 0..<1)
        let odds = bounceOdds
        var sum = 0.0
        for (kind, p) in odds {
            sum += p
            if r < sum { return kind }
        }
        return .plain
    }

    private func split(from src: Ball) {
        let sp = max(Double(hypot(src.v.dx, src.v.dy)), baseSpeed)
        let base = atan2(Double(src.v.dy), Double(src.v.dx))
        for d in [-0.45, 0.45] where balls.count < 6 {
            balls.append(Ball(p: src.p, v: CGVector(dx: cos(base + d) * sp, dy: sin(base + d) * sp)))
        }
    }
}

/// CADisplayLink keeps a strong reference to its target, so it points at this instead of the game.
private final class LinkProxy: NSObject {
    weak var game: Game?
    init(_ game: Game) { self.game = game }

    @objc func tick(_ link: CADisplayLink) {
        let t = link.targetTimestamp
        MainActor.assumeIsolated { game?.tick(t) }
    }
}
