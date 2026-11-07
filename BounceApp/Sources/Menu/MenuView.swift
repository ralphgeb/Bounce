import SwiftUI

enum Screen { case menu, bounce, maze, switcher, hue }

/// The main menu: four games, one section each, split by thin lines. Drag in a section and its
/// logo stretches after your finger and springs back (the others barely move); only a real tap,
/// without dragging, opens the game.
struct MenuView: View {
    let colors: Colors
    let open: (Screen) -> Void
    @Binding var showSettings: Bool

    @State private var drag: CGSize = .zero
    @State private var active: Int?
    @State private var pressed: Int?
    @State private var travelled: CGFloat = 0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let c = colors
        let s = Settings.shared
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 17))
                        .foregroundStyle(c.ink.opacity(0.45))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
            .padding(.trailing, 10)

            section(0, .bounce, word: "BOUNCE",
                    fills: [c.ink, c.accent, c.ink.opacity(0.72), c.ink.opacity(0.48), c.ink.opacity(0.28), c.ink.opacity(0.12)],
                    line: "Break the wall that never ends",
                    record: s.best > 0 ? "Best \(s.best)" : nil)
            divider
            section(1, .maze, word: "MAZE",
                    fills: [c.ink, c.accent, c.ink.opacity(0.5), c.ink.opacity(0.22)],
                    line: "Find your way out",
                    record: s.mazeDeepest > 1 ? "Level \(s.mazeDeepest)" : nil)
            divider
            section(2, .switcher, word: "SWITCH",
                    fills: [c.ink.opacity(0.65), c.ink.opacity(0.9), c.ink.opacity(0.15), c.accent, c.ink.opacity(0.4), c.ink.opacity(0.9)],
                    line: "Line up three of a shade",
                    record: s.switchBest > 0 ? "Best \(s.switchBest)" : nil)
            divider
            section(3, .hue, word: "HUE",
                    fills: HueColor.logo(c.accent),
                    line: "Put the colours in order",
                    record: s.hueSolved > 0 ? "\(s.hueSolved)/\(HueLevels.count)" : nil)
        }
        .padding(.bottom, 6)
        .onAppear {
            appeared = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8)) { appeared = true }
        }
    }

    private var divider: some View {
        Rectangle().fill(colors.ink.opacity(0.08)).frame(height: 1).padding(.horizontal, 22)
    }

    private func section(_ index: Int, _ screen: Screen, word: String, fills: [Color], line: String, record: String?) -> some View {
        VStack(spacing: 12) {
            ElasticLogo(word: word, fills: fills, ink: colors.ink, squareSize: 22, letterSize: 18,
                        drag: active == index ? drag : CGSize(width: drag.width * 0.1, height: drag.height * 0.1),
                        dropped: appeared)
            HStack(spacing: 8) {
                Text(line)
                    .font(.system(size: 13))
                    .foregroundStyle(colors.ink.opacity(0.55))
                if let record {
                    Text("·").foregroundStyle(colors.ink.opacity(0.3))
                    Text(record.uppercased())
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .tracking(1.2)
                        .foregroundStyle(colors.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.ink.opacity(pressed == index && travelled < 10 ? 0.04 : 0))
        .contentShape(Rectangle())
        .scaleEffect(pressed == index && travelled < 10 ? 0.985 : 1)
        .animation(.easeOut(duration: 0.15), value: pressed == index && travelled < 10)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 24)
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8).delay(Double(index) * 0.06), value: appeared)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if pressed == nil { travelled = 0 }
                    pressed = index
                    active = index
                    drag = v.translation
                    travelled = max(travelled, hypot(v.translation.width, v.translation.height))
                }
                .onEnded { _ in
                    // A tap opens the game; a drag only stretches the logo.
                    let tapped = travelled < 10
                    drag = .zero
                    pressed = nil
                    if tapped {
                        Haptics.tap(.medium)
                        open(screen)
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(word.capitalized). \(line)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open(screen) }
    }
}
