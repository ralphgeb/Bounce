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

    /// Level 1 is 10 × 14 rooms; each level adds 3 across and 4 down. Level 0 is the small one on the menu.
    static func generate(level: Int) -> Maze {
        var rng = SeededRandom(seed: UInt64(level) &* 7919 &+ 104_729)
        let cw = 7 + 3 * level, ch = 10 + 4 * level
        var m = Maze(width: cw * 2 + 1, height: ch * 2 + 1)
        func open(_ x: Int, _ y: Int) { m.wall[y * m.width + x] = false }

        // Carve with a depth-first walk from the bottom middle: long winding corridors.
        let sx = cw / 2, sy = ch - 1
        var visited = Array(repeating: false, count: cw * ch)
        var stack = [(sx, sy)]
        visited[sy * cw + sx] = true
        open(sx * 2 + 1, sy * 2 + 1)
        let dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        while let top = stack.last {
            let (cx, cy) = top
            var options: [(Int, Int)] = []
            for (dx, dy) in dirs {
                let nx = cx + dx, ny = cy + dy
                if nx >= 0, ny >= 0, nx < cw, ny < ch, !visited[ny * cw + nx] { options.append((dx, dy)) }
            }
            guard !options.isEmpty else { stack.removeLast(); continue }
            let (dx, dy) = options[Int(rng.next() % UInt64(options.count))]
            let nx = cx + dx, ny = cy + dy
            visited[ny * cw + nx] = true
            open(cx * 2 + 1 + dx, cy * 2 + 1 + dy)
            open(nx * 2 + 1, ny * 2 + 1)
            stack.append((nx, ny))
        }

        // Knock out a few walls so there are loops: more than one way, and easier to get lost.
        let extra = cw * ch / 14
        var made = 0, tries = 0
        while made < extra && tries < extra * 30 {
            tries += 1
            let x = 1 + Int(rng.next() % UInt64(m.width - 2)), y = 1 + Int(rng.next() % UInt64(m.height - 2))
            guard m.isWall(x, y), (x + y) % 2 == 1 else { continue }
            let across = !m.isWall(x - 1, y) && !m.isWall(x + 1, y) && m.isWall(x, y - 1) && m.isWall(x, y + 1)
            let down = !m.isWall(x, y - 1) && !m.isWall(x, y + 1) && m.isWall(x - 1, y) && m.isWall(x + 1, y)
            if across || down { open(x, y); made += 1 }
        }

        m.start = (sx * 2 + 1, sy * 2 + 1)
        m.goal = m.farthest(from: m.start)
        return m
    }

    /// The floor tile with the longest walk from here.
    private func farthest(from s: (x: Int, y: Int)) -> (x: Int, y: Int) {
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
        return best
    }
}

/// Light from the player: rays go out until they hit a wall, so walls throw shadows behind them.
enum Lighting {
    /// Casts a fan of rays (or a full circle when halfAngle ≥ π). Returns the lit area's outline,
    /// in tile units, and raises the brightness of every wall face a ray lands on (0...1, by distance).
    static func cast(_ maze: Maze, from o: CGPoint, angle: Double, halfAngle: Double, range: Double,
                     rays: Int, lit: inout [Int: Double]) -> [CGPoint] {
        let full = halfAngle >= .pi
        var outline: [CGPoint] = full ? [] : [o]
        let step = 0.045
        let count = full ? rays : rays + 1
        for k in 0..<count {
            let a = full ? Double(k) / Double(rays) * 2 * .pi
                         : angle - halfAngle + 2 * halfAngle * Double(k) / Double(rays)
            let dx = cos(a), dy = sin(a)
            var t = 0.0
            var hit = Int.min
            var end = CGPoint(x: o.x + dx * range, y: o.y + dy * range)
            var last = o
            while t < range {
                t += step
                let p = CGPoint(x: o.x + dx * t, y: o.y + dy * t)
                let tx = Int(floor(p.x)), ty = Int(floor(p.y))
                if maze.isWall(tx, ty) {
                    let id = Maze.key(tx, ty)
                    if hit == Int.min {
                        hit = id
                        let b = max(0, 1 - t / range)
                        if b > (lit[id] ?? 0) { lit[id] = b }
                    } else if id != hit {
                        end = last; break
                    }
                } else if hit != Int.min {
                    end = last; break
                }
                last = p
                if t >= range { end = p }
            }
            outline.append(end)
        }
        return outline
    }
}
