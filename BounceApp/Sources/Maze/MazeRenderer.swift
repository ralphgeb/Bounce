import SwiftUI

/// Draws a maze around the player. Everything is pitch black (pitch white in light mode) except what your light reaches:
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
        /// The map: 0 = normal, 1 = zoomed out over the whole maze. Still dark: only your light
        /// and your dots show, so you can see where the dots are compared to you.
        var map: Double = 0
        var seen: Set<Int> = []
        /// Where the view is centred (the player, or the middle of the maze on the map).
        var camera: CGPoint? = nil
        /// New dots: how many, and seconds since.
        var dotGain = 0
        var dotGainAge: Double = 9
        /// A fade to the background (0...1).
        var blink: Double = 0
        /// Map squares still to find, and how much of the whole maze is showing (0...1).
        var reveals: Set<Int> = []
        var revealAll: Double = 0
    }

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, scene s: Scene, colors c: Colors) {
        let T = s.tile
        let full = CGRect(origin: .zero, size: size)
        ctx.fill(Path(full), with: .color(c.background))

        let cam = s.camera ?? s.pos
        let mid = CGPoint(x: size.width / 2, y: size.height / 2)
        let origin = CGPoint(x: mid.x - cam.x * T, y: mid.y - cam.y * T)
        func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * T, y: origin.y + p.y * T) }
        let me = screen(s.pos)
        let gap = max(2, T * 0.07)
        func tileRect(_ x: Int, _ y: Int) -> CGRect {
            CGRect(x: origin.x + CGFloat(x) * T + gap / 2, y: origin.y + CGFloat(y) * T + gap / 2, width: T - gap, height: T - gap)
        }
        let x0 = Int(floor(-origin.x / T)) - 1, x1 = Int(ceil((size.width - origin.x) / T)) + 1
        let y0 = Int(floor(-origin.y / T)) - 1, y1 = Int(ceil((size.height - origin.y) / T)) + 1
        // At the start of each level you appear: the light comes up over the first second.
        let appear = s.dotGain > 0 ? min(1, s.dotGainAge / 0.9) : 1
        let k = s.lightStrength * (1 - pow(1 - appear, 2))

        // Settings › Maze › Show the walls: every wall, very faintly.
        if s.revealWalls {
            var all = Path()
            for y in y0...y1 { for x in x0...x1 where s.maze.isWall(x, y) { all.addRect(tileRect(x, y)) } }
            ctx.fill(all, with: .color(c.ink.opacity(0.09)))
        }

        // A map square found: every wall shows for a moment.
        if s.revealAll > 0.01 {
            var all = Path()
            for y in y0...y1 { for x in x0...x1 where s.maze.isWall(x, y) { all.addRect(tileRect(x, y)) } }
            ctx.fill(all, with: .color(c.ink.opacity(0.5 * s.revealAll)))
        }

        // The lit floor: only where the light reaches, fading out with distance.
        var light = Path()
        if s.light.count > 2 { light.addLines(s.light.map(screen)); light.closeSubpath() }
        let reach = CGFloat(s.range) * T
        ctx.drawLayer { l in
            l.clip(to: light)
            l.fill(Path(full), with: .radialGradient(
                Gradient(stops: [
                    .init(color: c.ink.opacity(0.34 * k), location: 0),
                    .init(color: c.ink.opacity(0.16 * k), location: 0.3),
                    .init(color: c.ink.opacity(0.05 * k), location: 0.7),
                    .init(color: c.ink.opacity(0), location: 1),
                ]), center: me, startRadius: 0, endRadius: reach))
            l.fill(Path(full), with: .radialGradient(
                Gradient(colors: [c.accent.opacity(0.22 * k), c.accent.opacity(0)]),
                center: me, startRadius: 0, endRadius: T * 2.2))
        }

        // Walls the light lands on: bright up close, gone into the dark further away.
        let steps = 32
        var bands: [Path] = Array(repeating: Path(), count: steps)
        for (key, b) in s.lit {
            let x = key % 20_000 - 16, y = key / 20_000 - 16
            guard x >= x0, x <= x1, y >= y0, y <= y1 else { continue }
            bands[min(steps - 1, Int(b * Double(steps)))].addRect(tileRect(x, y))
        }
        for (i, p) in bands.enumerated() where !p.isEmpty {
            let b = (Double(i) + 0.5) / Double(steps)
            ctx.fill(p, with: .color(c.ink.opacity(min(1, 0.06 + pow(b, 1.05) * 1.05) * k)))
        }

        // Dots you dropped stay where you left them, glowing softly; brighter when your light is on them.
        for key in s.dots {
            let x = key % 20_000 - 16, y = key / 20_000 - 16
            guard x >= x0, x <= x1, y >= y0, y <= y1 else { continue }
            let p = screen(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5))
            let inLight = light.contains(p)
            let d = hypot(Double(p.x - me.x), Double(p.y - me.y)) / Double(reach)
            let a = inLight ? max(0.6, 1 - d * 0.5) : 0.45
            let pulse = 1 + 0.12 * sin(s.time * 2.2 + Double(key % 7))
            let r = max(T * 0.12, 3 * CGFloat(s.map))
            let glow = max(r * 4.2, 10 * CGFloat(s.map)) * pulse
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - glow, y: p.y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [c.accent.opacity(0.42 * a), c.accent.opacity(0)]), center: p, startRadius: 0, endRadius: glow))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(c.accent.opacity(a)))
        }

        // Map squares: an accent outline around a smaller square, softly glowing, when your light finds them.
        for key in s.reveals {
            let x = key % 20_000 - 16, y = key / 20_000 - 16
            guard x >= x0, x <= x1, y >= y0, y <= y1 else { continue }
            let q = screen(CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5))
            guard light.contains(q) || hypot(Double(q.x - me.x), Double(q.y - me.y)) < Double(T) * 1.5 else { continue }
            let pulse = 1 + 0.08 * sin(s.time * 3 + Double(key % 5))
            let side = T * 0.42 * CGFloat(pulse)
            let r = CGRect(x: q.x - side / 2, y: q.y - side / 2, width: side, height: side)
            ctx.fill(Path(ellipseIn: r.insetBy(dx: -side, dy: -side)),
                     with: .radialGradient(Gradient(colors: [c.accent.opacity(0.35), c.accent.opacity(0)]), center: q, startRadius: 0, endRadius: side * 1.5))
            ctx.stroke(Path(r.insetBy(dx: 1, dy: 1)), with: .color(c.accent), lineWidth: 2)
            ctx.fill(Path(r.insetBy(dx: side * 0.3, dy: side * 0.3)), with: .color(c.accent))
        }

        // The way out: an accent star with its own glow, once your light reaches it.
        if s.showGoal {
            let g = CGPoint(x: Double(s.maze.goal.x) + 0.5, y: Double(s.maze.goal.y) + 0.5)
            let gs = screen(g)
            if light.contains(gs) || hypot(Double(g.x - s.pos.x), Double(g.y - s.pos.y)) < 1.5 {
                let pulse = 1 + 0.1 * sin(s.time * 3)
                ctx.fill(Path(ellipseIn: CGRect(x: gs.x - T * 1.6, y: gs.y - T * 1.6, width: T * 3.2, height: T * 3.2)),
                         with: .radialGradient(Gradient(colors: [c.accent.opacity(0.5), c.accent.opacity(0)]),
                                               center: gs, startRadius: 0, endRadius: T * 1.6))
                ctx.fill(Star.path(center: gs, radius: T * 0.34 * pulse, turn: s.time * 0.5), with: .color(c.accent))
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
            // You grow in from a tiny square, with a little overshoot, as the light comes up.
            let g = min(1, s.dotGainAge / 0.7)
            let grow = s.dotGain > 0 && g < 1 ? 1 + 2.4 * pow(g - 1, 3) + 1.4 * pow(g - 1, 2) : 1
            let base = T * 0.42 * CGFloat(max(0.05, grow))
            var w = base, h = base
            if let m = s.moving {
                let along = 1 + 0.22 * s.squash, across = 1 - 0.12 * s.squash
                if m.dx != 0 { w *= along; h *= across } else { h *= along; w *= across }
            }
            ctx.fill(Path(CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)), with: .color(c.accent))

            // On the map, a ring marks where you are.
            if s.map > 0.05 {
                let rr = 14 + 4 * sin(s.time * 4)
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)),
                           with: .color(c.accent.opacity(s.map)), lineWidth: 2)
            }

            // As you appear, one soft wave of light goes out from you.
            if s.dotGain > 0 && s.dotGainAge < 1.2 {
                let a = s.dotGainAge / 1.2
                let rr = T * (0.3 + 2.4 * CGFloat(a))
                ctx.stroke(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)),
                           with: .color(c.accent.opacity(0.5 * (1 - a))), lineWidth: 2)
            }
        }

        if s.flash > 0 {
            ctx.fill(Path(full), with: .color(c.accent.opacity(s.flash * 0.22)))
        }
        if s.blink > 0 {
            ctx.fill(Path(full), with: .color(c.background.opacity(s.blink)))
        }
    }
}
