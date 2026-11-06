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

    /// For the menu logo: two SwiftUI colours mixed.
    static func mix(_ a: Color, _ b: Color, _ t: Double) -> Color {
        rgb(mix(lab(RGB(a)), lab(RGB(b)), t)).color
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
    enum Corner { case light, dark, accent, second, accentSoft, secondDeep }
    enum Fixed { case border, alternate, cross, anchors, corners }

    let corners: [Corner]          // top left, top right, bottom left, bottom right
    let contrast: Double           // 1 = full; lower pulls the corners together (harder)
    let fixed: Fixed
    let shuffled: Int?             // nil = every square that isn't fixed
}

enum HueLevels {
    static let cols = 7
    static let rows = 8
    static let count = 10

    /// Easy to hard: from a bright four-colour board with its whole border fixed and a dozen squares
    /// out of place, to a narrow two-accent blend with only the four corners fixed.
    static let all: [HueLevel] = [
        HueLevel(corners: [.light, .accent, .second, .dark], contrast: 1.0, fixed: .border, shuffled: 12),
        HueLevel(corners: [.accent, .light, .dark, .second], contrast: 1.0, fixed: .border, shuffled: nil),
        HueLevel(corners: [.light, .accent, .dark, .accent], contrast: 0.95, fixed: .alternate, shuffled: nil),
        HueLevel(corners: [.accent, .second, .second, .accent], contrast: 0.9, fixed: .alternate, shuffled: nil),
        HueLevel(corners: [.light, .second, .accent, .dark], contrast: 0.85, fixed: .cross, shuffled: nil),
        HueLevel(corners: [.accent, .light, .accent, .dark], contrast: 0.8, fixed: .cross, shuffled: nil),
        HueLevel(corners: [.second, .accent, .light, .second], contrast: 0.72, fixed: .anchors, shuffled: nil),
        HueLevel(corners: [.accent, .second, .dark, .light], contrast: 0.66, fixed: .corners, shuffled: nil),
        HueLevel(corners: [.light, .accent, .accentSoft, .dark], contrast: 0.56, fixed: .corners, shuffled: nil),
        HueLevel(corners: [.accent, .second, .secondDeep, .accentSoft], contrast: 0.46, fixed: .corners, shuffled: nil),
    ]

    /// The colour every square should be, row by row.
    static func colors(_ level: HueLevel, accent: RGB, second: RGB) -> [RGB] {
        let white = HueColor.lab(RGB(0xF4F3EF)), black = HueColor.lab(RGB(0x1A1A1E))
        let a = HueColor.lab(accent), b = HueColor.lab(second)
        func corner(_ c: HueLevel.Corner) -> HueColor.Lab {
            switch c {
            case .light: return white
            case .dark: return black
            case .accent: return a
            case .second: return b
            case .accentSoft: return HueColor.mix(a, white, 0.55)
            case .secondDeep: return HueColor.mix(b, black, 0.45)
            }
        }
        var cs = level.corners.map(corner)
        // Lower contrast: pull each corner towards the middle colour.
        let mean = HueColor.Lab(l: cs.map(\.l).reduce(0, +) / 4, a: cs.map(\.a).reduce(0, +) / 4, b: cs.map(\.b).reduce(0, +) / 4)
        cs = cs.map { HueColor.mix(mean, $0, level.contrast) }
        var out: [RGB] = []
        for y in 0..<rows {
            for x in 0..<cols {
                let u = Double(x) / Double(cols - 1), v = Double(y) / Double(rows - 1)
                let top = HueColor.mix(cs[0], cs[1], u), bottom = HueColor.mix(cs[2], cs[3], u)
                out.append(HueColor.rgb(HueColor.mix(top, bottom, v)))
            }
        }
        return out
    }

    static func isFixed(_ level: HueLevel, _ i: Int) -> Bool {
        let x = i % cols, y = i / cols
        let edge = x == 0 || y == 0 || x == cols - 1 || y == rows - 1
        let corner = (x == 0 || x == cols - 1) && (y == 0 || y == rows - 1)
        switch level.fixed {
        case .border: return edge
        case .alternate: return edge && (x + y) % 2 == 0
        case .cross: return corner || (x == cols / 2 && (y == 0 || y == rows - 1)) || (y == rows / 2 && (x == 0 || x == cols - 1)) || (x == cols / 2 && y == rows / 2)
        case .anchors: return corner || ((x == 2 || x == 4) && (y == 2 || y == 5))
        case .corners: return corner
        }
    }

    /// The starting order: the same for everyone on each level. order[place] = the square there.
    static func shuffle(_ level: HueLevel, number: Int) -> [Int] {
        var rng = SeededRandom(seed: UInt64(number) &* 15_485_863 &+ 7)
        let n = cols * rows
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
