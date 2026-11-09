import SwiftUI
import UIKit

/// Colour maths for Hue: mixing in OKLab, so gradients look even to the eye.
enum HueColor {
    struct Lab { var l: Double; var a: Double; var b: Double }

    static func lab(_ c: RGB) -> Lab {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        let r = lin(c.r), g = lin(c.g), b = lin(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return Lab(l: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                   a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                   b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    static func rgb(_ c: Lab) -> RGB {
        let l = pow(c.l + 0.3963377774 * c.a + 0.2158037573 * c.b, 3)
        let m = pow(c.l - 0.1055613458 * c.a - 0.0638541728 * c.b, 3)
        let s = pow(c.l - 0.0894841775 * c.a - 1.2914855480 * c.b, 3)
        func gam(_ v: Double) -> Double {
            let x = max(0, min(1, v))
            return x <= 0.0031308 ? 12.92 * x : 1.055 * pow(x, 1 / 2.4) - 0.055
        }
        return RGB(r: gam(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                   g: gam(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                   b: gam(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }

    static func mix(_ a: Lab, _ b: Lab, _ t: Double) -> Lab {
        Lab(l: a.l + (b.l - a.l) * t, a: a.a + (b.a - a.a) * t, b: a.b + (b.b - a.b) * t)
    }

    /// Two SwiftUI colours mixed.
    static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        rgb(mix(lab(RGB(a)), lab(RGB(b)), t)).color
    }

    /// A shade of a colour: towards white (amount > 0) or black (amount < 0), -1...1.
    static func shade(_ c: Color, _ amount: Double) -> Color {
        let base = lab(RGB(c))
        let target = amount > 0 ? lab(RGB(0xFFFFFF)) : lab(RGB(0x000000))
        return rgb(mix(base, target, min(1, abs(amount)))).color
    }

    /// Hue's logo: three shades of the accent, light to deep.
    static func logo(_ accent: Color) -> [Color] {
        [shade(accent, 0.45), accent, shade(accent, -0.4)]
    }
}

extension RGB {
    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        self.init(r: Double(r), g: Double(g), b: Double(b))
    }
}

/// One Hue level: four corner colours the board blends between, how close together they are,
/// which squares are fixed in place (marked with a dot), and how many are shuffled.
struct HueLevel {
    enum Corner { case light, dark, accent, second, accentSoft, secondDeep, accentDeep, complement, analog }
    enum Fixed { case border, alternate, cross, anchors, corners, ends }

    let corners: [Corner]          // top left, top right, bottom left, bottom right
    let contrast: Double           // 1 = full; lower pulls the corners together (harder)
    let fixed: Fixed
    let shuffled: Int?             // nil = every square that isn't fixed
    var cols = 7
    var rows = 8
}

enum HueLevels {
    static let count = 50

    /// The tutorial: one row of five shades of the accent, the two ends fixed.
    static let tutorial = HueLevel(corners: [.accentSoft, .accentDeep, .accentSoft, .accentDeep], contrast: 1,
                                   fixed: .ends, shuffled: nil, cols: 5, rows: 1)
    /// Its starting order: the middle three out of place, two swaps to fix.
    static let tutorialOrder = [0, 2, 3, 1, 4]

    /// Easy to hard, very gently: the first ten are small-to-full, colourful boards with the border
    /// fixed and some squares out of place; the border stays fixed to level 25 and the colours only
    /// slowly draw closer, so the game stays fun and a long run feels within reach.
    static let all: [HueLevel] = (1...count).map(make)

    /// The first ten levels: four real colours each, built from the accent: its complement (across
    /// the colour wheel) and a neighbour, with light or dark, so the boards are colourful and fun.
    private static let firstPalettes: [[HueLevel.Corner]] = [
        [.light, .accent, .complement, .dark],
        [.accent, .analog, .light, .complement],
        [.complement, .accent, .light, .analog],
        [.light, .analog, .complement, .accent],
        [.accent, .light, .complement, .dark],
        [.analog, .complement, .accent, .light],
        [.light, .complement, .accent, .analog],
        [.accent, .second, .complement, .light],
        [.complement, .light, .dark, .accent],
        [.analog, .accent, .complement, .dark],
    ]

    private static let palettes: [[HueLevel.Corner]] = [
        [.light, .accent, .second, .dark],
        [.accent, .light, .dark, .second],
        [.light, .accent, .dark, .accent],          // one colour: white, the accent, black
        [.accentSoft, .second, .accent, .dark],
        [.light, .second, .accent, .dark],
        [.accent, .light, .accent, .dark],          // one colour
        [.second, .accent, .light, .second],
        [.accent, .second, .dark, .light],
        [.light, .accent, .accentSoft, .dark],      // one colour
        [.accent, .second, .secondDeep, .accentSoft],
    ]

    /// The first boards are small (5 × 5, 6 × 6, 6 × 7, 7 × 7), then 7 × 8 from level 5.
    private static let sizes: [(Int, Int)] = [(5, 5), (6, 6), (6, 7), (7, 7)]

    private static func make(_ n: Int) -> HueLevel {
        // Gentle all the way: level 25 is about as hard as the old level 6, level 50 a little more.
        let d = Double(n - 1) / Double(count - 1)
        let fixed: HueLevel.Fixed = n <= 25 ? .border : n <= 40 ? .alternate : .cross
        let partial = [6, 9, 12, 15, 18, 20, 22, 24, 26, 28]   // squares out of place on levels 1 to 10
        let shuffled: Int? = n <= partial.count ? partial[n - 1] : nil
        let size = n <= sizes.count ? sizes[n - 1] : (7, 8)
        let all = firstPalettes + palettes
        let corners = n <= firstPalettes.count ? firstPalettes[n - 1] : all[(n - 1) % all.count]
        return HueLevel(corners: corners,
                        contrast: 1 - 0.3 * pow(d, 1.1),       // 0.85 on level 25, 0.7 on level 50
                        fixed: fixed, shuffled: shuffled, cols: size.0, rows: size.1)
    }

    /// The colour every square should be, row by row.
    static func colors(_ level: HueLevel, accent: RGB, second: RGB) -> [RGB] {
        let white = HueColor.lab(RGB(0xF4F3EF)), black = HueColor.lab(RGB(0x1A1A1E))
        let a = HueColor.lab(accent), b = HueColor.lab(second)
        /// The accent turned round the colour wheel (in OKLCh), a little softer or lighter.
        func rotate(_ c: HueColor.Lab, by turn: Double, chroma k: Double, lightness dl: Double) -> HueColor.Lab {
            let ch = hypot(c.a, c.b) * k, h = atan2(c.b, c.a) + turn
            return HueColor.Lab(l: min(0.92, c.l + dl), a: ch * cos(h), b: ch * sin(h))
        }
        func corner(_ c: HueLevel.Corner) -> HueColor.Lab {
            switch c {
            case .light: return white
            case .dark: return black
            case .accent: return a
            case .second: return b
            case .accentSoft: return HueColor.mix(a, white, 0.55)
            case .secondDeep: return HueColor.mix(b, black, 0.45)
            case .accentDeep: return HueColor.mix(a, black, 0.5)
            case .complement: return rotate(a, by: .pi, chroma: 0.9, lightness: 0.02)
            case .analog: return rotate(a, by: 0.75, chroma: 1, lightness: 0.08)
            }
        }
        let cols = level.cols, rows = level.rows
        var cs = level.corners.map(corner)
        // Lower contrast: pull each corner towards the middle colour.
        let mean = HueColor.Lab(l: cs.map(\.l).reduce(0, +) / 4, a: cs.map(\.a).reduce(0, +) / 4, b: cs.map(\.b).reduce(0, +) / 4)
        cs = cs.map { HueColor.mix(mean, $0, level.contrast) }
        var out: [RGB] = []
        for y in 0..<rows {
            for x in 0..<cols {
                let u = cols > 1 ? Double(x) / Double(cols - 1) : 0, v = rows > 1 ? Double(y) / Double(rows - 1) : 0
                let top = HueColor.mix(cs[0], cs[1], u), bottom = HueColor.mix(cs[2], cs[3], u)
                out.append(HueColor.rgb(HueColor.mix(top, bottom, v)))
            }
        }
        return out
    }

    static func isFixed(_ level: HueLevel, _ i: Int) -> Bool {
        let cols = level.cols, rows = level.rows
        let x = i % cols, y = i / cols
        let edge = x == 0 || y == 0 || x == cols - 1 || y == rows - 1
        let corner = (x == 0 || x == cols - 1) && (y == 0 || y == rows - 1)
        switch level.fixed {
        case .border: return edge
        case .alternate: return edge && (x + y) % 2 == 0
        case .cross: return corner || (x == cols / 2 && (y == 0 || y == rows - 1)) || (y == rows / 2 && (x == 0 || x == cols - 1)) || (x == cols / 2 && y == rows / 2)
        case .anchors: return corner || ((x == 2 || x == 4) && (y == 2 || y == 5))
        case .corners: return corner
        case .ends: return x == 0 || x == cols - 1
        }
    }

    /// The starting order: the same for everyone on each level. order[place] = the square there.
    static func shuffle(_ level: HueLevel, number: Int) -> [Int] {
        var rng = SeededRandom(seed: UInt64(number) &* 15_485_863 &+ 7)
        let n = level.cols * level.rows
        var order = Array(0..<n)
        var movable = (0..<n).filter { !isFixed(level, $0) }
        if let k = level.shuffled {
            // Only k squares change places among themselves.
            for i in stride(from: movable.count - 1, to: 0, by: -1) {
                movable.swapAt(i, Int(rng.next() % UInt64(i + 1)))
            }
            movable = Array(movable.prefix(k))
        }
        // Shuffle until no square is still in its own place.
        var picked = movable
        repeat {
            for i in stride(from: picked.count - 1, to: 0, by: -1) {
                picked.swapAt(i, Int(rng.next() % UInt64(i + 1)))
            }
        } while zip(movable, picked).contains { $0 == $1 } && movable.count > 1
        for (place, square) in zip(movable, picked) { order[place] = square }
        return order
    }
}
