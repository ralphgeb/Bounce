import CoreGraphics
import Foundation

/// Repeatable random numbers, so every player gets the same maze for each level.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A grid of wall and floor tiles. Each level is bigger than the last, and the way out is the
/// spot farthest from where you start.
struct Maze {
    let width: Int
    let height: Int
    private(set) var wall: [Bool]
    private(set) var start = (x: 1, y: 1)
    private(set) var goal = (x: 1, y: 1)

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        wall = Array(repeating: true, count: width * height)
    }

    func isWall(_ x: Int, _ y: Int) -> Bool {
        x < 0 || y < 0 || x >= width || y >= height || wall[y * width + x]
    }

    /// One number per tile, for sets and dictionaries (works outside the grid too).
    static func key(_ x: Int, _ y: Int) -> Int { (y + 16) * 20_000 + (x + 16) }

    /// How many levels there are.
    static let levels = 20

    /// Rooms across and down: tiny to start (5 × 7 on level 1, 6 × 8, 7 × 9…), growing faster from
    /// level 5 (38 × 53 on level 20).
    static func size(_ level: Int) -> (cols: Int, rows: Int) {
        let cw = 4 + level + Int(Double(max(0, level - 4)) * 0.9)
        return (cw, Int(Double(cw) * 1.4))
    }

    /// The learning curve is slow: the first levels are tiny, with almost no dead ends, so nobody gets
    /// lost on level 1; then they grow, branch a little more and keep fewer dead ends open, so level 10
    /// is a fair challenge and level 20 a real one. Of 12 tries, each level keeps the maze whose way
    /// out is nearest a walk that grows with the level.
    static func generate(level: Int) -> Maze {
        let (cw, ch) = size(level)
        let target = Int(Double(2 * cw * ch) * (0.22 + 0.012 * Double(level)))
        var best: (maze: Maze, steps: Int)?
        for attempt in 0..<12 {
            let m = build(level: level, attempt: attempt)
            if best == nil || abs(m.steps - target) < abs(best!.steps - target) { best = m }
        }
        return best!.maze
    }

    private static func build(level: Int, attempt: Int) -> (maze: Maze, steps: Int) {
        var rng = SeededRandom(seed: UInt64(level) &* 7919 &+ 104_729 &+ UInt64(attempt) &* 1_000_003)
        func roll(_ n: Int) -> Int { Int(rng.next() % UInt64(n)) }
        let (cw, ch) = size(level)
        var m = Maze(width: cw * 2 + 1, height: ch * 2 + 1)
        func open(_ x: Int, _ y: Int) { m.wall[y * m.width + x] = false }

        // Carve a growing tree from the bottom middle. Mostly it carries on from the newest room
        // (long winding corridors); more and more often it branches from an older one.
        let branchy = min(0.1, Double(level - 1) * 0.1 / 19)
        let sx = cw / 2, sy = ch - 1
        var visited = Array(repeating: false, count: cw * ch)
        var active = [(sx, sy)]
        visited[sy * cw + sx] = true
        open(sx * 2 + 1, sy * 2 + 1)
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        while !active.isEmpty {
            let branch = Double(roll(1000)) / 1000 < branchy
            let pick = branch ? roll(active.count) : active.count - 1
            let (cx, cy) = active[pick]
            var options: [(Int, Int)] = []
            for (dx, dy) in dirs {
                let nx = cx + dx, ny = cy + dy
                if nx >= 0, ny >= 0, nx < cw, ny < ch, !visited[ny * cw + nx] { options.append((dx, dy)) }
            }
            guard !options.isEmpty else { active.remove(at: pick); continue }
            let (dx, dy) = options[roll(options.count)]
            let nx = cx + dx, ny = cy + dy
            visited[ny * cw + nx] = true
            open(cx * 2 + 1 + dx, cy * 2 + 1 + dy)
            open(nx * 2 + 1, ny * 2 + 1)
            active.append((nx, ny))
        }

        // Knock out some walls to make loops: more ways round, so you're less often stuck.
        let extra = Int(Double(cw * ch) * (0.03 + 0.001 * Double(level)))
        var made = 0, tries = 0
        while made < extra && tries < extra * 40 {
            tries += 1
            let x = 1 + roll(m.width - 2), y = 1 + roll(m.height - 2)
            guard m.isWall(x, y), (x + y) % 2 == 1 else { continue }
            let across = !m.isWall(x - 1, y) && !m.isWall(x + 1, y) && m.isWall(x, y - 1) && m.isWall(x, y + 1)
            let down = !m.isWall(x, y - 1) && !m.isWall(x, y + 1) && m.isWall(x - 1, y) && m.isWall(x + 1, y)
            if across || down { open(x, y); made += 1 }
        }

        // Open most dead ends into the next corridor on early levels (90% on level 1), fewer later
        // (30% from level 20), so wrong turns are rare at first and short later.
        for cy in 0..<ch {
            for cx in 0..<cw {
                let x = cx * 2 + 1, y = cy * 2 + 1
                var walls: [(Int, Int)] = []
                for (dx, dy) in dirs where m.isWall(x + dx, y + dy) { walls.append((dx, dy)) }
                guard walls.count == 3, roll(100) < max(30, 90 - 3 * level) else { continue }
                let inside = walls.filter { d in
                    let nx = x + d.0 * 2, ny = y + d.1 * 2
                    return nx > 0 && ny > 0 && nx < m.width - 1 && ny < m.height - 1
                }
                guard !inside.isEmpty else { continue }
                let d = inside[roll(inside.count)]
                open(x + d.0, y + d.1)
            }
        }

        m.start = (sx * 2 + 1, sy * 2 + 1)
        let far = m.farthest(from: m.start)
        m.goal = far.tile
        return (m, far.steps)
    }

    /// The floor tile with the longest walk from here.
    private func farthest(from s: (x: Int, y: Int)) -> (tile: (x: Int, y: Int), steps: Int) {
        var dist = Array(repeating: -1, count: width * height)
        var queue = [(s.x, s.y)], head = 0
        dist[s.y * width + s.x] = 0
        var best = s
        while head < queue.count {
            let (x, y) = queue[head]; head += 1
            let d = dist[y * width + x]
            if d > dist[best.y * width + best.x] { best = (x, y) }
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !isWall(x + dx, y + dy) {
                let i = (y + dy) * width + x + dx
                if dist[i] < 0 { dist[i] = d + 1; queue.append((x + dx, y + dy)) }
            }
        }
        return (best, dist[best.y * width + best.x])
    }
}

/// Light from the player: rays go out until they hit a wall, so walls throw shadows behind them.
enum Lighting {
    /// Rays slip past the corner where two lit walls meet, leaving that corner square dark.
    /// A wall with a lit wall beside it, a lit wall above or below it, and floor in the corner
    /// between those two gets lit from them.
    static func fillCorners(_ maze: Maze, lit: inout [Int: Double], floors: Set<Int>) {
        var candidates = Set<Int>()
        for key in lit.keys {
            let x = key % 20_000 - 16, y = key / 20_000 - 16
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where maze.isWall(x + dx, y + dy) {
                let k = Maze.key(x + dx, y + dy)
                if lit[k] == nil { candidates.insert(k) }
            }
        }
        var add: [Int: Double] = [:]
        for k in candidates {
            let x = k % 20_000 - 16, y = k / 20_000 - 16
            for (sx, sy) in [(1, 1), (1, -1), (-1, 1), (-1, -1)] {
                // The floor in the corner must itself be in the light, so walls in shadow stay dark.
                guard let a = lit[Maze.key(x + sx, y)], let b = lit[Maze.key(x, y + sy)],
                      !maze.isWall(x + sx, y + sy), floors.contains(Maze.key(x + sx, y + sy)) else { continue }
                add[k] = max(add[k] ?? 0, min(a, b) * 0.92)
            }
        }
        for (k, v) in add { lit[k] = v }
    }

    /// Casts a fan of rays (or a full circle when halfAngle ≥ π). Each ray stops at the first wall it
    /// meets. Returns the lit floor's outline, in tile units, marks the first wall each ray lands on,
    /// and collects the floor tiles the light crosses.
    static func cast(_ maze: Maze, from o: CGPoint, angle: Double, halfAngle: Double, range: Double,
                     rays: Int, lit: inout [Int: Double], floors: inout Set<Int>) -> [CGPoint] {
        let full = halfAngle >= .pi
        var outline: [CGPoint] = full ? [] : [o]
        let count = full ? rays : rays + 1
        for k in 0..<count {
            let a = full ? Double(k) / Double(rays) * 2 * .pi
                         : angle - halfAngle + 2 * halfAngle * Double(k) / Double(rays)
            let dx = cos(a), dy = sin(a)
            // Walk the grid square by square (DDA), so each ray stops exactly on a wall's edge.
            let ox = Double(o.x), oy = Double(o.y)
            var mx = Int(floor(ox)), my = Int(floor(oy))
            let deltaX = dx == 0 ? 1e30 : abs(1 / dx), deltaY = dy == 0 ? 1e30 : abs(1 / dy)
            let stepX = dx < 0 ? -1 : 1, stepY = dy < 0 ? -1 : 1
            var sideX = dx < 0 ? (ox - Double(mx)) * deltaX : (Double(mx) + 1 - ox) * deltaX
            var sideY = dy < 0 ? (oy - Double(my)) * deltaY : (Double(my) + 1 - oy) * deltaY
            var end = CGPoint(x: ox + dx * range, y: oy + dy * range)
            floors.insert(Maze.key(mx, my))
            while true {
                let t: Double
                if sideX < sideY { t = sideX; sideX += deltaX; mx += stepX } else { t = sideY; sideY += deltaY; my += stepY }
                if t >= range { break }
                if maze.isWall(mx, my) {
                    // The light stops at the first wall: that wall lights up, nothing behind it does.
                    let id = Maze.key(mx, my)
                    let b = max(0, 1 - t / range)
                    if b > (lit[id] ?? 0) { lit[id] = b }
                    end = CGPoint(x: ox + dx * t, y: oy + dy * t)
                    break
                }
                floors.insert(Maze.key(mx, my))
            }
            outline.append(end)
        }
        return outline
    }
}
