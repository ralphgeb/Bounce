import SwiftUI

/// Draws a maze around the player: darkness, the walls you remember, the cone of light with the
/// shadows the walls throw, the way out when you can see it, and you.
enum MazeRenderer {
    struct Scene {
        var maze: Maze
        var pos: CGPoint
        var cone: [CGPoint]
        var halo: [CGPoint]
        var lit: [Int: Double]
        var seen: Set<Int> = []
        var range: Double
        var tile: CGFloat
        var moving: MazeGame.Dir? = nil
        var squash: Double = 0
        var bump: (dir: MazeGame.Dir, amount: Double)? = nil
        var flash: Double = 0
        var time: Double = 0
        var showGoal = true
        var showPlayer = true
        var lightStrength: Double = 1
        /// Where the player sits on screen, as a fraction of the size.
        var anchor = CGPoint(x: 0.5, y: 0.5)
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, scene s: Scene, colors c: Colors) {
        let T = s.tile
        let full = CGRect(origin: .zero, size: size)
        ctx.fill(Path(full), with: .color(c.background))

        let me = CGPoint(x: size.width * s.anchor.x, y: size.height * s.anchor.y)
        let origin = CGPoint(x: me.x - s.pos.x * T, y: me.y - s.pos.y * T)
        func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * T, y: origin.y + p.y * T) }
        let gap = max(1.5, T * 0.09)
        func tileRect(_ x: Int, _ y: Int) -> CGRect {
            CGRect(x: origin.x + CGFloat(x) * T + gap / 2, y: origin.y + CGFloat(y) * T + gap / 2, width: T - gap, height: T - gap)
        }

        // The tiles on screen.
        let x0 = Int(floor(-origin.x / T)) - 1, x1 = Int(ceil((size.width - origin.x) / T)) + 1
        let y0 = Int(floor(-origin.y / T)) - 1, y1 = Int(ceil((size.height - origin.y) / T)) + 1

        // Walls you have already lit stay faintly in memory.
        if !s.seen.isEmpty {
            var memory = Path()
            for y in y0...y1 {
                for x in x0...x1 where s.maze.isWall(x, y) && s.seen.contains(Maze.key(x, y)) {
                    memory.addRect(tileRect(x, y))
                }
            }
            ctx.fill(memory, with: .color(c.ink.opacity(0.055)))
        }

        // The light: a cone in front and a small glow around you, stopped by the walls.
        var light = Path()
        if s.cone.count > 2 { light.addLines(s.cone.map(screen)); light.closeSubpath() }
        if s.halo.count > 2 { light.addLines(s.halo.map(screen)); light.closeSubpath() }
        let reach = CGFloat(s.range) * T
        let k = s.lightStrength
        ctx.drawLayer { l in
            l.clip(to: light)
            l.fill(Path(full), with: .radialGradient(
                Gradient(stops: [
                    .init(color: c.ink.opacity(0.26 * k), location: 0),
                    .init(color: c.ink.opacity(0.11 * k), location: 0.35),
                    .init(color: c.ink.opacity(0.035 * k), location: 0.75),
                    .init(color: c.ink.opacity(0), location: 1),
                ]), center: me, startRadius: 0, endRadius: reach))
            l.fill(Path(full), with: .radialGradient(
                Gradient(colors: [c.accent.opacity(0.16 * k), c.accent.opacity(0)]),
                center: me, startRadius: 0, endRadius: T * 2.8))
        }

        // Lit walls: brighter the closer they are. Everything behind them stays in shadow.
        var bands: [Path] = Array(repeating: Path(), count: 8)
        for (key, b) in s.lit {
            let x = key % 20_000 - 16, y = key / 20_000 - 16
            guard x >= x0, x <= x1, y >= y0, y <= y1 else { continue }
            let level = min(7, Int(pow(b, 1.15) * 8))
            bands[level].addRect(tileRect(x, y))
        }
        for (i, p) in bands.enumerated() where !p.isEmpty {
            ctx.fill(p, with: .color(c.ink.opacity((0.08 + 0.78 * (Double(i) + 0.5) / 8) * k)))
        }

        // The way out: an accent circle with its own glow, once your light reaches it (or you're next to it).
        if s.showGoal {
            let g = CGPoint(x: Double(s.maze.goal.x) + 0.5, y: Double(s.maze.goal.y) + 0.5)
            let gs = screen(g)
            let near = hypot(Double(g.x - s.pos.x), Double(g.y - s.pos.y)) < 1.8
            if near || light.contains(gs) {
                let pulse = 1 + 0.08 * sin(s.time * 3)
                ctx.fill(Path(ellipseIn: CGRect(x: gs.x - T * 1.8, y: gs.y - T * 1.8, width: T * 3.6, height: T * 3.6)),
                         with: .radialGradient(Gradient(colors: [c.accent.opacity(0.45), c.accent.opacity(0)]),
                                               center: gs, startRadius: 0, endRadius: T * 1.8))
                let r = T * 0.26 * pulse
                ctx.fill(Path(ellipseIn: CGRect(x: gs.x - r, y: gs.y - r, width: r * 2, height: r * 2)), with: .color(c.accent))
            }
        }

        // You: an accent square that stretches a little as it slides and nudges a wall when blocked.
        if s.showPlayer {
            var p = me
            if let b = s.bump {
                let push = T * 0.1 * sin(b.amount * .pi)
                p.x += CGFloat(b.dir.dx) * push
                p.y += CGFloat(b.dir.dy) * push
            }
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - T * 1.2, y: p.y - T * 1.2, width: T * 2.4, height: T * 2.4)),
                     with: .radialGradient(Gradient(colors: [c.accent.opacity(0.32 * k), c.accent.opacity(0)]),
                                           center: p, startRadius: 0, endRadius: T * 1.2))
            let base = T * 0.56
            var w = base, h = base
            if let m = s.moving {
                let along = 1 + 0.2 * s.squash, across = 1 - 0.12 * s.squash
                if m.dx != 0 { w *= along; h *= across } else { h *= along; w *= across }
            }
            ctx.fill(Path(CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)), with: .color(c.accent))
        }

        if s.flash > 0 {
            ctx.fill(Path(full), with: .color(c.accent.opacity(s.flash * 0.22)))
        }
    }
}

/// A small maze with the light sweeping round: behind the Maze landing page and on the menu.
struct MazePreview: View {
    let colors: Colors
    var tilesAcross: CGFloat = 9
    var strength: Double = 1

    private static let maze = Maze.generate(level: 0)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                let t = tl.date.timeIntervalSinceReferenceDate
                let m = Self.maze
                let o = CGPoint(x: Double(m.start.x) + 0.5, y: Double(m.start.y) + 0.5)
                let angle = reduceMotion ? -Double.pi / 2 : t * 0.45
                var lit: [Int: Double] = [:]
                let cone = Lighting.cast(m, from: o, angle: angle, halfAngle: 0.62, range: 7.5, rays: 120, lit: &lit)
                let halo = Lighting.cast(m, from: o, angle: 0, halfAngle: .pi, range: 1.6, rays: 40, lit: &lit)
                let scene = MazeRenderer.Scene(maze: m, pos: o, cone: cone, halo: halo, lit: lit, range: 7.5,
                                               tile: size.width / tilesAcross, time: t, showGoal: false,
                                               lightStrength: strength)
                MazeRenderer.draw(&ctx, size: size, scene: scene, colors: colors)
            }
        }
    }
}
