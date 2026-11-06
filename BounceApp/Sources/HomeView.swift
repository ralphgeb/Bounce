import SwiftUI

/// The landing page: six squares over B O U N C E, how the twist works, and Start.
struct HomeView: View {
    let game: Game
    let colors: Colors
    @Binding var showSettings: Bool

    @State private var dropped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let letters = Array("BOUNCE")

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(colors.ink.opacity(0.45))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 12)

            Spacer()
            logo
            rules.padding(.top, 34)
            Text(result)
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(colors.ink.opacity(0.5))
                .frame(minHeight: 20)
                .padding(.top, 30)
            OutlineButton(title: game.phase == .over ? "Again" : "Start", colors: colors) { game.start() }
                .padding(.top, 22)
            Spacer()
            Spacer()
        }
        .onAppear {
            dropped = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55)) { dropped = true }
        }
    }

    /// Six squares, one over each letter: the main colour, the accent over the O, then lighter shades.
    private var logo: some View {
        let fills: [Color] = [colors.ink, colors.accent, colors.ink.opacity(0.72), colors.ink.opacity(0.48), colors.ink.opacity(0.28), colors.ink.opacity(0.12)]
        return HStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { i in
                VStack(spacing: 18) {
                    Rectangle()
                        .fill(fills[i])
                        .frame(width: 34, height: 34)
                        .offset(y: dropped ? 0 : -80)
                        .opacity(dropped ? 1 : 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55).delay(Double(i) * 0.07), value: dropped)
                    Text(String(letters[i]))
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(colors.ink)
                }
                .frame(width: 40)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Bounce")
        .accessibilityAddTraits(.isHeader)
    }

    private var rules: some View {
        VStack(alignment: .leading, spacing: 10) {
            rule(colors.accent, "Accent square splits the ball in three")
            rule(colors.ink, "Skip the paddle to chain ×2, ×3, ×4")
            rule(colors.ink.opacity(0.4), "Break 20 in a row for an extra life")
        }
    }

    private func rule(_ fill: Color, _ text: String) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(fill).frame(width: 12, height: 12)
            Text(text).font(.system(size: 13)).foregroundStyle(colors.ink.opacity(0.6))
        }
    }

    private var result: String {
        guard game.phase == .over else {
            let best = Settings.shared.best
            return best > 0 ? "Best \(best)" : " "
        }
        if game.newBest { return "New best · \(game.score) · \(formatTime(game.elapsed))" }
        return "\(game.score) · \(formatTime(game.elapsed)) · best \(Settings.shared.best)"
    }
}
