import SwiftUI

enum Screen { case menu, bounce, maze, switcher }

/// The main menu: three games, one section each, split by thin lines. Drag in a section and its
/// logo stretches after your finger and springs back; the other two barely move.
struct MenuView: View {
    let colors: Colors
    let open: (Screen) -> Void
    @Binding var showSettings: Bool

    @State private var drag: CGSize = .zero
    @State private var active: Int?
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let c = colors
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
            .padding(.leading, 22)
            .padding(.trailing, 10)

            section(0, .bounce, word: "BOUNCE",
                    fills: [c.ink, c.accent, c.ink.opacity(0.72), c.ink.opacity(0.48), c.ink.opacity(0.28), c.ink.opacity(0.12)],
                    line: "Break the wall that never ends",
                    record: Settings.shared.best > 0 ? "Best \(Settings.shared.best)" : nil)
            divider
            section(1, .maze, word: "MAZE",
                    fills: [c.ink, c.accent, c.ink.opacity(0.5), c.ink.opacity(0.22)],
                    line: "Find your way in the dark",
                    record: Settings.shared.mazeDeepest > 1 ? "Deepest level \(Settings.shared.mazeDeepest)" : nil)
            divider
            section(2, .switcher, word: "SWITCH",
                    fills: [c.ink.opacity(0.62), c.ink, c.ink.opacity(0.16), c.accent, c.ink.opacity(0.36), c.ink],
                    line: "Line up three of a shade",
                    record: Settings.shared.switchBest > 0 ? "Best \(Settings.shared.switchBest)" : nil)
        }
        .onAppear {
            appeared = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8)) { appeared = true }
        }
    }

    private var divider: some View {
        Rectangle().fill(colors.ink.opacity(0.08)).frame(height: 1).padding(.horizontal, 22)
    }

    private func section(_ index: Int, _ screen: Screen, word: String, fills: [Color], line: String, record: String?) -> some View {
        Button {
            Haptics.tap(.medium)
            open(screen)
        } label: {
            VStack(spacing: 16) {
                ElasticLogo(word: word, fills: fills, ink: colors.ink, squareSize: 26, letterSize: 21,
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
            .contentShape(Rectangle())
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 24)
            .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8).delay(Double(index) * 0.08), value: appeared)
        }
        .buttonStyle(SectionPress(colors: colors))
        .simultaneousGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { v in active = index; drag = v.translation }
                .onEnded { _ in drag = .zero }
        )
        .accessibilityLabel("\(word.capitalized). \(line)")
    }
}

private struct SectionPress: ButtonStyle {
    let colors: Colors
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(colors.ink.opacity(configuration.isPressed ? 0.04 : 0))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
