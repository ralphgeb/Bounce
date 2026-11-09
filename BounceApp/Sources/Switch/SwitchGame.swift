import SwiftUI

/// One piece on the board: a shade (four of the main colour, and the accent) and maybe a power.
struct Gem {
    enum Power: CaseIterable {
        case row       // cut corners, line across: clears its row
        case column    // cut corners, line down: clears its column
        case bomb      // circle: clears the squares around it
        case shade     // diamond: clears every square of its shade
    }

    let id: Int
    var shade: Int
    var power: Power?
    /// Where it's drawn, in cells (it slides and falls towards its place on the grid).
    var x: Double
    var y: Double
    var vy: Double = 0
    var fade: Double = 1     // dying pieces fade from 1 to 0
    var grow: Double = 1     // new pieces grow in
}

/// Switch: swipe a square to swap it with its neighbour; three or more of a shade in a line clear.
/// Four in a line makes a row or column clearer, five a circle, a T or an L a diamond; a diamond
/// also turns up after every 120 squares cleared. No limit on moves; a hint when stuck.
@MainActor
@Observable
final class SwitchGame {
    enum Phase { case ready, playing, paused, over }

    private enum Step {
        case idle
        case swapping(Int, Int, back: Bool)
        case clearing(Double)
        case falling
        /// Tutorial: the squares about to clear are highlighted for a moment first.
        case showing(Double, Outcome)
    }

    let cols = 8
    let rows = 8
    /// Six colours: three of one family and three of the accent (the last one, index 5, is the
    /// accent itself, which the tutorial uses).
    let shades = 6

    private(set) var phase: Phase = .ready
    private(set) var score = 0
    private(set) var moves = 0           // moves made
    /// A move to show when you ask for a hint: the two cells, and how long the hint stays.
    @ObservationIgnored private(set) var hint: (a: Int, b: Int, life: Double)?
    @ObservationIgnored private var clearedSinceDiamond = 0
    @ObservationIgnored private var diamondDue = false
    private(set) var combo = 1
    private(set) var frame = 0
    private(set) var toast: String?
    private(set) var toastID = 0
    private(set) var newBest = false
    private(set) var lastScore: Int?

    @ObservationIgnored private(set) var grid: [Gem?] = []
    @ObservationIgnored private(set) var dying: [Gem] = []
    @ObservationIgnored private(set) var particles: [Particle] = []
    /// Rows or columns just cleared: index, across or down, fading life.
    @ObservationIgnored private(set) var sweeps: [(index: Int, across: Bool, life: Double)] = []
    /// Circles just gone off: centre cell and life.
    @ObservationIgnored private(set) var blasts: [(x: Int, y: Int, life: Double)] = []
    @ObservationIgnored var pressed: Int?
    /// Seconds since the game started, for the diamonds' shine.
    @ObservationIgnored private(set) var clock: Double = 0
    /// The first-time tutorial, played on the board: each step sets up a small pattern and shows
    /// the one swipe that makes it work.
    let coach = Coach()
    /// Shades of the main colour and the accent, or five colours from the theme.
    enum Palette { case mono, colour }
    private(set) var palette: Palette = .mono
    /// The tutorial stage being played, and the swipe it's waiting for.
    private(set) var tutorial: Int?
    @ObservationIgnored private(set) var guide: (cell: Int, dx: Int, dy: Int)?
    @ObservationIgnored private var awaiting = false

    @ObservationIgnored private var step: Step = .idle
    @ObservationIgnored private var nextID = 0
    private let ticker = FrameTicker()
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    init() {
        ticker.onTick = { [weak self] dt in
            MainActor.assumeIsolated { self?.tick(dt) }
        }
        fill()
    }

    var busy: Bool { if case .idle = step { return false } else { return true } }

    // MARK: Phases

    func start(_ palette: Palette) {
        self.palette = palette
        score = 0; moves = 0; combo = 1; newBest = false
        clearedSinceDiamond = 0; diamondDue = false; hint = nil
        dying = []; particles = []; sweeps = []; blasts = []
        phase = .playing
        ticker.start()
        coach.begin("switch", steps: [
            .init(text: "Swipe up to swap these two.\nThree of a kind in a line clear.", waitFor: .swap),
            .init(text: "Four in a line\nmakes a line clearer.", waitFor: .swap),
            .init(text: "Match the line clearer\nto clear its whole row.", waitFor: .swap),
            .init(text: "Five in a line\nmakes a circle.", waitFor: .swap),
            .init(text: "Match the circle to clear\nthe squares around it.", waitFor: .swap),
            .init(text: "A T or an L shape\nmakes a diamond.", waitFor: .swap),
            .init(text: "Match the diamond: every square\nof its colour clears.", waitFor: .swap),
            .init(text: "That's all of it.\nMake lines, chain them,\nand go for a high score.\nStuck? Tap Hint.", waitFor: .tapToContinue),
        ], onFinish: { [weak self] in self?.endTutorial() })
        if coach.active {
            setUpStage(0)
        } else {
            dropInBoard()
        }
    }

    private func dropInBoard() {
        tutorial = nil; guide = nil; awaiting = false
        fill()
        // Drop the whole board in from above.
        for i in grid.indices { grid[i]?.y -= Double(rows) + 1 }
        step = .falling
        Sound.shared.play("whoosh", volume: 0.5)
    }

    private func endTutorial() {
        guard tutorial != nil else { return }
        score = 0; moves = 0; combo = 1
        clearedSinceDiamond = 0; diamondDue = false
        dying = []; sweeps = []; blasts = []
        dropInBoard()
    }

    // MARK: Tutorial

    private struct Stage {
        var cells: [(x: Int, y: Int, power: Gem.Power?)]
        var move: (x: Int, y: Int, dx: Int, dy: Int)
        var sprinkle = false     // a few more of the colour around, for the diamond to clear
    }

    /// Each stage: squares of one colour (the accent), and the one swipe that completes the pattern.
    private let stages: [Stage] = [
        Stage(cells: [(1, 4, nil), (2, 4, nil), (3, 5, nil)], move: (3, 5, 0, -1)),
        Stage(cells: [(1, 4, nil), (2, 4, nil), (4, 4, nil), (3, 5, nil)], move: (3, 5, 0, -1)),
        Stage(cells: [(1, 4, nil), (2, 4, .row), (3, 5, nil)], move: (3, 5, 0, -1)),
        Stage(cells: [(1, 4, nil), (2, 4, nil), (4, 4, nil), (5, 4, nil), (3, 5, nil)], move: (3, 5, 0, -1)),
        Stage(cells: [(1, 4, nil), (2, 4, .bomb), (3, 5, nil)], move: (3, 5, 0, -1)),
        Stage(cells: [(1, 3, nil), (3, 3, nil), (2, 4, nil), (2, 5, nil), (2, 2, nil)], move: (2, 2, 0, 1)),
        Stage(cells: [(1, 4, nil), (2, 4, .shade), (3, 5, nil)], move: (3, 5, 0, -1), sprinkle: true),
    ]

    private func setUpStage(_ n: Int) {
        guard n < stages.count else {
            tutorial = nil; guide = nil
            return
        }
        tutorial = n
        let st = stages[n]
        let accent = shades - 1
        var g: [Gem?] = Array(repeating: nil, count: cols * rows)
        var special = Set<Int>()
        for c in st.cells {
            let i = idx(c.x, c.y)
            g[i] = newGem(x: c.x, y: Double(c.y), shade: accent, power: c.power)
            special.insert(i)
        }
        // Everything else: the other colours, with no lines made, and none made by the shown swipe
        // except the pattern's own.
        let from = idx(st.move.x, st.move.y), to = idx(st.move.x + st.move.dx, st.move.y + st.move.dy)
        let expected = st.cells.count == 5 && st.cells.contains(where: { $0.y == 3 }) ? 2 : 1
        for _ in 0..<200 {
            for y in 0..<rows {
                for x in 0..<cols where !special.contains(idx(x, y)) {
                    var s: Int
                    repeat {
                        s = Int.random(in: 0..<(shades - 1))
                    } while (x >= 2 && g[idx(x - 1, y)]?.shade == s && g[idx(x - 2, y)]?.shade == s)
                        || (y >= 2 && g[idx(x, y - 1)]?.shade == s && g[idx(x, y - 2)]?.shade == s)
                    g[idx(x, y)] = newGem(x: x, y: Double(y), shade: s)
                }
            }
            var shadesNow = g.map { $0?.shade }
            guard runs({ shadesNow[$0] }).isEmpty else { continue }
            shadesNow.swapAt(from, to)
            let after = runs { shadesNow[$0] }
            if after.count == expected && after.allSatisfy({ $0.cells.allSatisfy { shadesNow[$0] == accent } }) { break }
        }
        if st.sprinkle {
            for (x, y) in [(0, 0), (5, 1), (3, 7), (6, 6), (0, 7)] where !special.contains(idx(x, y)) {
                g[idx(x, y)]?.shade = accent
            }
        }
        for i in g.indices { g[i]?.grow = 0.2 }
        grid = g
        guide = (idx(st.move.x, st.move.y), st.move.dx, st.move.dy)
        awaiting = false
        step = .idle
    }

    /// After the stage's swipe has played out, move on.
    private func stageDone() {
        guard let n = tutorial else { return }
        guide = nil
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.7))
            guard let self, self.tutorial == n else { return }
            self.coach.next()
            // After the last one, the closing card; the real game starts when it's tapped away.
            if n + 1 < self.stages.count { self.setUpStage(n + 1) }
        }
    }

    func pause() { if phase == .playing { phase = .paused } }
    func resume() { if phase == .paused { phase = .playing } }

    /// End the game (from pause) and keep the score.
    func home() {
        if phase != .ready {
            lastScore = score
            let s = Settings.shared
            // Best scores are kept once everything is unlocked.
            if Unlock.shared.isUnlocked && score > s.switchBest { s.switchBest = score; newBest = score > 0 }
        }
        phase = .ready
        ticker.stop()
    }

    /// Show one move that works.
    func showHint() {
        guard phase == .playing, !busy, let m = findMove() else { return }
        hint = (m.0, m.1, 2.2)
        Haptics.tap(.light)
        Sound.shared.play("glass", volume: 0.7)
    }

    // MARK: Board

    private func idx(_ x: Int, _ y: Int) -> Int { y * cols + x }

    private func newGem(x: Int, y: Double, shade: Int, power: Gem.Power? = nil) -> Gem {
        nextID += 1
        return Gem(id: nextID, shade: shade, power: power, x: Double(x), y: y)
    }

    /// A fresh board with no lines already made and at least one move.
    private func fill() {
        repeat {
            grid = Array(repeating: nil, count: cols * rows)
            for y in 0..<rows {
                for x in 0..<cols {
                    var s: Int
                    repeat {
                        s = Int.random(in: 0..<shades)
                    } while (x >= 2 && grid[idx(x - 1, y)]?.shade == s && grid[idx(x - 2, y)]?.shade == s)
                        || (y >= 2 && grid[idx(x, y - 1)]?.shade == s && grid[idx(x, y - 2)]?.shade == s)
                    grid[idx(x, y)] = newGem(x: x, y: Double(y), shade: s)
                }
            }
        } while !hasMove()
    }

    private struct Run { var cells: [Int]; var across: Bool }

    /// What a set of lines will do: the squares to clear, the powers to make, and the effects.
    fileprivate struct Outcome {
        var clear: Set<Int>
        var make: [(cell: Int, power: Gem.Power)]
        var sweeps: [(index: Int, across: Bool, life: Double)]
        var blasts: [(x: Int, y: Int, life: Double)]
        var powered: Bool
        /// The areas a power clears, in cells (for the tutorial's highlight).
        var regions: [(x0: Int, y0: Int, x1: Int, y1: Int)]
    }

    /// Tutorial: the squares about to clear, highlighted.
    @ObservationIgnored private(set) var highlight = Set<Int>()
    @ObservationIgnored private(set) var regions: [(x0: Int, y0: Int, x1: Int, y1: Int)] = []
    @ObservationIgnored private var slowClear = false

    private func runs(_ shadeAt: (Int) -> Int?) -> [Run] {
        var out: [Run] = []
        for y in 0..<rows {
            var x = 0
            while x < cols {
                guard let s = shadeAt(idx(x, y)) else { x += 1; continue }
                var e = x + 1
                while e < cols, shadeAt(idx(e, y)) == s { e += 1 }
                if e - x >= 3 { out.append(Run(cells: (x..<e).map { idx($0, y) }, across: true)) }
                x = e
            }
        }
        for x in 0..<cols {
            var y = 0
            while y < rows {
                guard let s = shadeAt(idx(x, y)) else { y += 1; continue }
                var e = y + 1
                while e < rows, shadeAt(idx(x, e)) == s { e += 1 }
                if e - y >= 3 { out.append(Run(cells: (y..<e).map { idx(x, $0) }, across: false)) }
                y = e
            }
        }
        return out
    }

    private func currentRuns() -> [Run] { runs { self.grid[$0]?.shade } }

    private func hasMove() -> Bool { findMove() != nil }

    private func findMove() -> (Int, Int)? {
        var shadesNow = grid.map { $0?.shade }
        for y in 0..<rows {
            for x in 0..<cols {
                for (dx, dy) in [(1, 0), (0, 1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx < cols, ny < rows else { continue }
                    let a = idx(x, y), b = idx(nx, ny)
                    shadesNow.swapAt(a, b)
                    let found = !runs { shadesNow[$0] }.isEmpty
                    shadesNow.swapAt(a, b)
                    if found { return (a, b) }
                }
            }
        }
        return nil
    }

    // MARK: Moves

    /// Swipe from a cell in a direction: swap with that neighbour.
    func swipe(from cell: Int, dx: Int, dy: Int) {
        guard phase == .playing, !busy else { return }
        // In the tutorial, only the swipe it shows.
        if tutorial != nil {
            guard let g = guide, g.cell == cell, g.dx == dx, g.dy == dy else {
                Haptics.tap(.soft, intensity: 0.3)
                Sound.shared.play("bump", volume: 0.35, gap: 0.15)
                return
            }
            awaiting = true
        }
        let x = cell % cols + dx, y = cell / cols + dy
        guard x >= 0, y >= 0, x < cols, y < rows else { return }
        let other = idx(x, y)
        grid.swapAt(cell, other)
        hint = nil
        step = .swapping(cell, other, back: false)
        Haptics.tap(.light, intensity: 0.5)
        Sound.shared.play("swish_soft", volume: 0.7)
    }

    private func afterSwap(_ a: Int, _ b: Int, back: Bool) {
        if back { step = .idle; return }
        let found = currentRuns()
        if found.isEmpty {
            // No line: swap back.
            grid.swapAt(a, b)
            step = .swapping(a, b, back: true)
            Haptics.tap(.soft, intensity: 0.4)
            Sound.shared.play("bump", volume: 0.45)
            return
        }
        moves += 1
        combo = 1
        resolve(found, focus: [b, a])
    }

    /// Clear the lines, make new powers, and set off any powers caught up in it.
    private func resolve(_ found: [Run], focus: [Int]) {
        var clear = Set(found.flatMap(\.cells))
        var make: [(cell: Int, power: Gem.Power)] = []

        // Four in a line: a row clearer (across) or a column clearer (down). Five or more: a circle.
        for r in found where r.cells.count >= 4 {
            let at = focus.first(where: { r.cells.contains($0) }) ?? r.cells[r.cells.count / 2]
            make.append((at, r.cells.count >= 5 ? .bomb : (r.across ? .row : .column)))
        }
        // A line across and a line down that cross (a T or an L): a diamond where they meet.
        var across = Set<Int>(), down = Set<Int>()
        for r in found { if r.across { across.formUnion(r.cells) } else { down.formUnion(r.cells) } }
        for corner in across.intersection(down) {
            make.removeAll { $0.cell == corner }
            make.append((corner, .shade))
        }
        // One power per cell.
        var taken = Set<Int>()
        make = make.filter { taken.insert($0.cell).inserted }
        // Don't overwrite a power that's about to go off.
        make.removeAll { grid[$0.cell]?.power != nil }
        for m in make { clear.remove(m.cell) }

        // Powers in the cleared cells go off, and so do any they reach.
        var queue = clear.filter { grid[$0]?.power != nil }
        var done = Set<Int>()
        var sound = false
        var newSweeps: [(index: Int, across: Bool, life: Double)] = []
        var newBlasts: [(x: Int, y: Int, life: Double)] = []
        var newRegions: [(x0: Int, y0: Int, x1: Int, y1: Int)] = []
        while let c = queue.popFirst() {
            guard !done.contains(c), let g = grid[c], let p = g.power else { continue }
            done.insert(c)
            let cx = c % cols, cy = c / cols
            var reach: [Int] = []
            switch p {
            case .row:
                reach = (0..<cols).map { idx($0, cy) }
                newSweeps.append((cy, true, 1))
                newRegions.append((0, cy, cols - 1, cy))
            case .column:
                reach = (0..<rows).map { idx(cx, $0) }
                newSweeps.append((cx, false, 1))
                newRegions.append((cx, 0, cx, rows - 1))
            case .bomb:
                for y in max(0, cy - 1)...min(rows - 1, cy + 1) {
                    for x in max(0, cx - 1)...min(cols - 1, cx + 1) { reach.append(idx(x, y)) }
                }
                newBlasts.append((cx, cy, 1))
                newRegions.append((max(0, cx - 1), max(0, cy - 1), min(cols - 1, cx + 1), min(rows - 1, cy + 1)))
            case .shade:
                reach = grid.indices.filter { grid[$0]?.shade == g.shade }
                newBlasts.append((cx, cy, 1))
                for r in reach { newRegions.append((r % cols, r / cols, r % cols, r / cols)) }
            }
            sound = true
            for r in reach where !clear.contains(r) && !make.contains(where: { $0.cell == r }) {
                clear.insert(r)
                if grid[r]?.power != nil { queue.insert(r) }
            }
        }

        let outcome = Outcome(clear: clear, make: make, sweeps: newSweeps, blasts: newBlasts, powered: sound, regions: newRegions)
        if tutorial != nil && sound {
            // Tutorial: when a power goes off, show what it reaches before it goes, slowly.
            highlight = clear
            regions = newRegions
            slowClear = true
            step = .showing(1.5, outcome)
            Haptics.tap(.light, intensity: 0.6)
            return
        }
        apply(outcome)
    }

    private func apply(_ o: Outcome) {
        let clear = o.clear, make = o.make, sound = o.powered
        highlight = []
        regions = []
        sweeps.append(contentsOf: o.sweeps)
        blasts.append(contentsOf: o.blasts)
        score += clear.count * 10 * combo
        // Every 120 squares cleared, a diamond turns up among the new squares.
        clearedSinceDiamond += clear.count
        if clearedSinceDiamond >= 120 { clearedSinceDiamond -= 120; diamondDue = true }
        for c in clear {
            guard var g = grid[c] else { continue }
            burst(g)
            g.fade = 1
            dying.append(g)
            grid[c] = nil
        }
        for m in make {
            grid[m.cell]?.power = m.power
            grid[m.cell]?.grow = 0.4
        }
        if sound { Haptics.tap(.heavy) } else { Haptics.tap(.rigid, intensity: 0.6) }
        // A marimba note that climbs with each chain; a swish when a power goes off; a chime
        // when you make one.
        Sound.shared.note(2 + (combo - 1) * 2, volume: 0.45)
        if sound { Sound.shared.play("clear") }
        if !make.isEmpty { Sound.shared.play("power") }
        if combo >= 2 { show("×\(combo)") }
        step = .clearing(slowClear ? 0.8 : tutorial != nil ? 0.35 : 0.2)
    }

    /// Everything falls into the gaps; new pieces drop in from the top.
    private func collapse() {
        for x in 0..<cols {
            var write = rows - 1
            for y in stride(from: rows - 1, through: 0, by: -1) {
                if let g = grid[idx(x, y)] {
                    if write != y { grid[idx(x, write)] = g; grid[idx(x, y)] = nil }
                    write -= 1
                }
            }
            var k = 0
            while write >= 0 {
                k += 1
                // Powers only come from your lines, and one diamond after every 120 squares cleared.
                var power: Gem.Power?
                if diamondDue && tutorial == nil && Bool.random() { power = .shade; diamondDue = false }
                grid[idx(x, write)] = newGem(x: x, y: -Double(k), shade: Int.random(in: 0..<shades), power: power)
                write -= 1
            }
        }
        // In the tutorial everything still falls, but nothing lines up by itself: only your move clears.
        if tutorial != nil { defuse() }
        step = .falling
    }

    /// Would this colour at (x, y) make three in a line with its neighbours?
    private func makesLine(_ s: Int, _ x: Int, _ y: Int) -> Bool {
        func at(_ x: Int, _ y: Int) -> Int? {
            guard x >= 0, y >= 0, x < cols, y < rows else { return nil }
            return grid[idx(x, y)]?.shade
        }
        if at(x - 1, y) == s && at(x + 1, y) == s { return true }
        if at(x - 1, y) == s && at(x - 2, y) == s { return true }
        if at(x + 1, y) == s && at(x + 2, y) == s { return true }
        if at(x, y - 1) == s && at(x, y + 1) == s { return true }
        if at(x, y - 1) == s && at(x, y - 2) == s { return true }
        if at(x, y + 1) == s && at(x, y + 2) == s { return true }
        return false
    }

    /// Changes the colour of squares (newest first, never the accent ones the lesson is about) until
    /// no line is made, so a fall never sets off a chain.
    private func defuse() {
        for _ in 0..<60 {
            let found = currentRuns()
            guard let run = found.first else { return }
            let pick = run.cells
                .filter { grid[$0]?.shade != shades - 1 && grid[$0]?.power == nil }
                .max { (grid[$0]?.id ?? 0) < (grid[$1]?.id ?? 0) } ?? run.cells[0]
            let x = pick % cols, y = pick / cols
            var options: [Int] = []
            for s in 0..<(shades - 1) where s != grid[pick]?.shade && !makesLine(s, x, y) { options.append(s) }
            grid[pick]?.shade = options.randomElement() ?? (grid[pick]!.shade + 1) % (shades - 1)
        }
    }

    private func settled() {
        let found = currentRuns()
        if !found.isEmpty {
            combo += 1
            resolve(found, focus: [])
            return
        }
        combo = 1
        step = .idle
        if awaiting { awaiting = false; stageDone(); return }
        if tutorial != nil { return }
        if !hasMove() {
            show("Shuffle")
            Sound.shared.play("whoosh", volume: 0.6)
            repeat {
                for i in grid.indices { grid[i]?.shade = Int.random(in: 0..<shades) }
            } while !currentRuns().isEmpty || !hasMove()
        }
    }

    private func show(_ text: String) {
        toast = text; toastID += 1
        let id = toastID
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.0))
            guard let self, self.toastID == id else { return }
            self.toast = nil
        }
    }

    private func burst(_ g: Gem) {
        for _ in 0..<5 {
            particles.append(Particle(p: CGPoint(x: g.x + .random(in: 0.1...0.9), y: g.y + .random(in: 0.1...0.9)),
                                      v: CGVector(dx: .random(in: -2.5...2.5), dy: .random(in: -3.5...1)),
                                      life: 1, size: CGFloat(g.shade)))
        }
    }

    // MARK: Loop

    private func tick(_ dt: Double) {
        guard phase == .playing else { return }
        clock += dt
        var moving = false
        for i in grid.indices {
            guard var g = grid[i] else { continue }
            let tx = Double(i % cols), ty = Double(i / cols)
            // Sideways and upward moves slide; falling accelerates.
            if g.x != tx {
                let d = tx - g.x, s = 9 * dt
                g.x = abs(d) <= s ? tx : g.x + (d > 0 ? s : -s)
                moving = true
            }
            if g.y < ty {
                g.vy = min(22, g.vy + 60 * dt)
                g.y = min(ty, g.y + g.vy * dt)
                if g.y >= ty { g.vy = 0 }
                moving = true
            } else if g.y > ty {
                let s = 9 * dt
                g.y = g.y - ty <= s ? ty : g.y - s
                moving = true
            }
            if g.grow < 1 { g.grow = min(1, g.grow + dt * 5) }
            grid[i] = g
        }
        for i in dying.indices.reversed() {
            dying[i].fade -= dt * (slowClear ? 1.6 : 5)
            if dying[i].fade <= 0 { dying.remove(at: i) }
        }
        for i in particles.indices.reversed() {
            particles[i].life -= dt * 2.2
            if particles[i].life <= 0 { particles.remove(at: i); continue }
            particles[i].p.x += particles[i].v.dx * dt
            particles[i].p.y += particles[i].v.dy * dt
            particles[i].v.dy += 9 * dt
        }
        for i in sweeps.indices.reversed() {
            sweeps[i].life -= dt * 3
            if sweeps[i].life <= 0 { sweeps.remove(at: i) }
        }
        for i in blasts.indices.reversed() {
            blasts[i].life -= dt * 2.5
            if blasts[i].life <= 0 { blasts.remove(at: i) }
        }
        if var h = hint {
            h.life -= dt
            hint = h.life > 0 ? h : nil
        }

        switch step {
        case .idle:
            break
        case let .swapping(a, b, back: back):
            if !moving { afterSwap(a, b, back: back) }
        case let .clearing(t):
            let left = t - dt
            if left > 0 {
                step = .clearing(left)
            } else {
                slowClear = false
                collapse()
            }
        case let .showing(t, o):
            let left = t - dt
            if left <= 0 { apply(o) } else { step = .showing(left, o) }
        case .falling:
            if !moving { settled() }
        }
        frame &+= 1
    }
}
