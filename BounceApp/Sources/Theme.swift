import SwiftUI
import UIKit

/// A colour from a hex number, as in Halo and Scout.
struct RGB: Hashable {
    let r: Double, g: Double, b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

/// The two colours a look uses in one appearance. The accent is shared.
struct Palette: Hashable {
    let ink: RGB
    let background: RGB
}

/// A look: five of the presets from Halo and Scout. Each has its own app icon.
struct Look: Identifiable, Hashable {
    let id: String
    let name: String
    let light: Palette
    let dark: Palette
    let accent: RGB

    /// The alternate icon's name in the asset catalog (Graphite is the main icon).
    var iconName: String? { id == "graphite" ? nil : "AppIcon-\(name)" }

    static let all: [Look] = [
        Look(id: "graphite", name: "Graphite",
             light: .init(ink: RGB(0x121214), background: RGB(0xF9F9F7)),
             dark: .init(ink: RGB(0xF2F2ED), background: RGB(0x090909)), accent: RGB(0xFF6129)),
        Look(id: "ocean", name: "Ocean",
             light: .init(ink: RGB(0x0E2A47), background: RGB(0xF4F7FA)),
             dark: .init(ink: RGB(0xE4EEF7), background: RGB(0x07111C)), accent: RGB(0x1FC8B4)),
        Look(id: "sky", name: "Sky",
             light: .init(ink: RGB(0x33557A), background: RGB(0xEEF6FD)),
             dark: .init(ink: RGB(0xDCEBFA), background: RGB(0x0A1320)), accent: RGB(0x6FB6F2)),
        Look(id: "blush", name: "Blush",
             light: .init(ink: RGB(0x6B3A50), background: RGB(0xFDF2F6)),
             dark: .init(ink: RGB(0xF9E4EC), background: RGB(0x170C11)), accent: RGB(0xF08BB0)),
        Look(id: "forest", name: "Forest",
             light: .init(ink: RGB(0x1C3324), background: RGB(0xF5F7F3)),
             dark: .init(ink: RGB(0xE5EFE6), background: RGB(0x08100B)), accent: RGB(0xE8B04A)),
    ]
}

/// Light, dark, or following the iPhone.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Automatic"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// The colours for what's on screen now.
struct Colors {
    let ink: Color
    let background: Color
    let accent: Color

    /// Ink mixed into the background: for the tougher and softer blocks.
    func shade(_ amount: Double) -> Color { ink.opacity(amount) }
}

/// Everything the player chooses, kept on the iPhone.
@MainActor
@Observable
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    var lookID: String { didSet { defaults.set(lookID, forKey: "look") } }
    var mode: AppearanceMode { didSet { defaults.set(mode.rawValue, forKey: "mode") } }
    var haptics: Bool { didSet { defaults.set(haptics, forKey: "haptics") } }
    var best: Int { didSet { defaults.set(best, forKey: "best") } }
    var longest: Double { didSet { defaults.set(longest, forKey: "longest") } }
    /// Maze: the deepest level reached, and the fastest time for each level ("1": seconds).
    var mazeDeepest: Int { didSet { defaults.set(mazeDeepest, forKey: "maze.deepest") } }
    var mazeTimes: [String: Double] { didSet { defaults.set(mazeTimes, forKey: "maze.times") } }
    /// Maze: level 20's way out has been found.
    var mazeFinished: Bool { didSet { defaults.set(mazeFinished, forKey: "maze.finished") } }
    /// Hue: how many levels are solved, and the fewest swaps for each ("1": swaps).
    var hueSolved: Int { didSet { defaults.set(hueSolved, forKey: "hue.solved") } }
    var hueBest: [String: Int] { didSet { defaults.set(hueBest, forKey: "hue.best") } }
    /// Switch: the best score.
    var switchBest: Int { didSet { defaults.set(switchBest, forKey: "switch.best") } }

    private init() {
        lookID = defaults.string(forKey: "look") ?? "graphite"
        mode = AppearanceMode(rawValue: defaults.string(forKey: "mode") ?? "") ?? .system
        haptics = defaults.object(forKey: "haptics") as? Bool ?? true
        best = defaults.integer(forKey: "best")
        longest = defaults.double(forKey: "longest")
        mazeDeepest = defaults.integer(forKey: "maze.deepest")
        mazeTimes = defaults.dictionary(forKey: "maze.times") as? [String: Double] ?? [:]
        mazeFinished = defaults.bool(forKey: "maze.finished")
        switchBest = defaults.integer(forKey: "switch.best")
        hueSolved = defaults.integer(forKey: "hue.solved")
        hueBest = defaults.dictionary(forKey: "hue.best") as? [String: Int] ?? [:]
    }

    var look: Look { Look.all.first { $0.id == lookID } ?? Look.all[0] }

    /// A second accent for Hue's two-colour levels: the accent of another look.
    var secondAccent: RGB {
        let i = Look.all.firstIndex { $0.id == look.id } ?? 0
        return Look.all[(i + 2) % Look.all.count].accent
    }

    /// Maze is always played in the dark: the look's dark colours.
    var darkColors: Colors {
        Colors(ink: look.dark.ink.color, background: look.dark.background.color, accent: look.accent.color)
    }

    func colors(_ scheme: ColorScheme) -> Colors {
        let p = scheme == .dark ? look.dark : look.light
        return Colors(ink: p.ink.color, background: p.background.color, accent: look.accent.color)
    }
}

/// Small uppercase labels, as in the other apps.
extension View {
    func bounceLabel(_ c: Colors) -> some View {
        self.font(.system(size: 11, weight: .semibold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(c.ink.opacity(0.5))
    }
}

enum Haptics {
    @MainActor static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light, intensity: CGFloat = 1) {
        guard Settings.shared.haptics else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: intensity)
    }

    @MainActor static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard Settings.shared.haptics else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

/// "42s" or "3m 05s".
func formatTime(_ s: Double) -> String {
    let t = Int(s)
    return t < 60 ? "\(t)s" : "\(t / 60)m \(String(format: "%02d", t % 60))s"
}
