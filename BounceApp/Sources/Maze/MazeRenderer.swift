import SwiftUI

/// Draws a maze around the player. Everything is pitch black except what your light reaches:
/// the floor glows faintly, walls light up by how close they are, and they throw shadows behind them.
enum MazeRenderer {
    struct Scene {
        var maze: Maze
        var pos: CGPoint
        var light: [CGPoint]
        var lit: [Int: Double]
        var dots: Set<Int> = []
        var range: Double
        var tile: CGFloat
        var moving: MazeGame.Dir? = nil
        var squash: Double = 0
        var bump: (dir: MazeGame.Dir, amount: Double)? = nil
        var flash: Double = 0
        var time: Double = 0
        var showGoal = true
        var showPlayer = true
        var revealWalls = false
        var lightStrength: Double = 1
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, scene s: Scene, colors c: Colors) {
        let T = s.tile
        let full = CGRect(origin: .zero, size: size)
        ctx.fill(Path(full), with: .color(.black))

        let me = CGPoint(x: size.width / 2, y: size.height / 2)
        let origin = CGPoint(x: me.x - s.pos.x * T, y: me.y - s.pos.y * T)
        func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * T, y: origin.y + p.y * T) }
        let gap = max(2, T * 0.07)
        func tileRect(_ x: Int, _ y: Int) -> CGRect {
            CGRect(x: origin.x + CGFloat(x) * T + gap / 2, y: origin.y + CGFloat(y) * T + gap / 2, width: T - gap, height: T - gap)
        }
        let x0 = Int(floor(-origin.x / T)) - 1, x1 = Int(ceil((size.width - origin.x) / T)) + 1
        let y0 = Int(floor(-origin.y / T)) - 1, y1 = Int(ceil((size.height - origin.y) / T)) + 1
        let k = s.lightStrength

        // Settings › Maze › Show the walls: every wall, very faintly.
        if s.revealWalls {
            var all = Path()
            for y in y0...y1 { for x in x0...x1 where s.maze.isWall(x, y) { all.addRect(tileRect(x, y)) } }
            ctx.fill(all, with: .color(c.ink.opacity(0.09)))
        }

        // The lit floor: only where the light reaches, fading out with distance.
        var light = Path()
        if s.light.count > 2 { light.addLines(s.light.map(screen)); light.closeSubpath() }
        let reach = CGFloat(s.range) * T
        ctx.drawLayer { l in
            l.clip(to: light)
            l.fill(Path(full), with: .radialGradient(
                Gradient(stops: [
                    .init(color: c.ink.opacity(0.16 * k), location: 0),
                    .init(color: c.ink.opacity(0.07 * k), location: 0.3),
                    .init(color: c.ink.opacity(0.02 * k), location: 0.7),
                    .init(color: c.ink.opacity(0), location: 1),
                ]), center: me, startRadius: 0, endRadius: reach))
            l.fill(Path(full), with: .radialGradient(
                Gradient(colors: [c.accent.opacity(0.14 * k), c.accent.opacity(0)]),
                center: me, startRadius: 0, endRadius: T * 2.2))
        }

        // Walls the light lands on: bright up close, gone into the dark further away.
        var bands: [Path] = Array(repeating: Path(), count: 10)
        for (key, b) in s.lit {
            let x = key % 20_000 - 16, y = key / 20_000 - 16
            guard x >= x0, x <= x1, y >= y0, y <= y1 else { continue }
            bands[min(9, Int(b * 10))].addRect(tileRect(x, y))
        }
        for (i, p) in bands.enumerated() where !p.isEmpty {
            let b = (Double(i) + 0.5) / 10
            ctx.fill(p, with: .color(c.ink.opacity(pow(b, 1.5) * 0.92 * k)))
        }

        // Dots you dropped, when your light finds them again.
        for key in s.dots {
            let x = key % 20_000 - 16, y = key / 20_000 - 16
            let p = screen(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5))
            guard light.contains(p) else { continue }
            let d = hypot(Double(p.x - me.x), Double(p.y - me.y)) / Double(reach)
            let a = max(0.25, 1 - d)
            let r = T * 0.085
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 3, y: p.y - r * 3, width: r * 6, height: r * 6)),
                     with: .radialGradient(Gradient(colors: [c.accent.opacity(0.35 * a), c.accent.opacity(0)]), center: p, startRadius: 0, endRadius: r * 3))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(c.accent.opacity(a)))
        }

        // The way out: an accent circle with its own glow, once your light reaches it.
        if s.showGoal {
            let g = CGPoint(x: Double(s.maze.goal.x) + 0.5, y: Double(s.maze.goal.y) + 0.5)
            let gs = screen(g)
            if light.contains(gs) || hypot(Double(g.x - s.pos.x), Double(g.y - s.pos.y)) < 1.5 {
                let pulse = 1 + 0.1 * sin(s.time * 3)
                ctx.fill(Path(ellipseIn: CGRect(x: gs.x - T * 1.6, y: gs.y - T * 1.6, width: T * 3.2, height: T * 3.2)),
                         with: .radialGradient(Gradient(colors: [c.accent.opacity(0.5), c.accent.opacity(0)]),
                                               center: gs, startRadius: 0, endRadius: T * 1.6))
                let r = T * 0.2 * pulse
                ctx.fill(Path(ellipseIn: CGRect(x: gs.x - r, y: gs.y - r, width: r * 2, height: r * 2)), with: .color(c.accent))
            }
        }

        // You: the light source. An accent square that stretches as it slides and nudges a wall when blocked.
        if s.showPlayer {
            var p = me
            if let b = s.bump {
                let push = T * 0.08 * sin(b.amount * .pi)
                p.x += CGFloat(b.dir.dx) * push
                p.y += CGFloat(b.dir.dy) * push
            }
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - T, y: p.y - T, width: T * 2, height: T * 2)),
                     with: .radialGradient(Gradient(colors: [c.accent.opacity(0.4 * k), c.accent.opacity(0)]),
                                           center: p, startRadius: 0, endRadius: T))
            let base = T * 0.42
            var w = base, h = base
            if let m = s.moving {
                let along = 1 + 0.22 * s.squash, across = 1 - 0.12 * s.squash
                if m.dx != 0 { w *= along; h *= across } else { h *= along; w *= across }
            }
            ctx.fill(Path(CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)), with: .color(c.accent))
        }

        if s.flash > 0 {
            ctx.fill(Path(full), with: .color(c.accent.opacity(s.flash * 0.22)))
        }
    }
}

/// A small maze lit from the middle, the light gently breathing: behind the Maze landing page.
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
                let range = 5 * (1 + 0.04 * sin(t * 1.3))
                var lit: [Int: Double] = [:]
                let light = Lighting.cast(m, from: o, angle: 0, halfAngle: .pi, range: range, rays: 240, lit: &lit)
                let scene = MazeRenderer.Scene(maze: m, pos: o, light: light, lit: lit, range: range,
                                               tile: size.width / tilesAcross, time: t, showGoal: false,
                                               lightStrength: strength)
                MazeRenderer.draw(&ctx, size: size, scene: scene, colors: colors)
            }
        }
    }
}
