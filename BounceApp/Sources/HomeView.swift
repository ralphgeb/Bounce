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
            Spacer()
            // Low on the screen, where the thumb is.
            OutlineButton(title: game.phase == .over ? "Again" : "Start", colors: colors) { game.start() }
                .padding(.bottom, 64)
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

    /// The four special squares, drawn as they look in the game.
    private var rules: some View {
        VStack(alignment: .leading, spacing: 12) {
            rule(Rectangle().fill(colors.accent).frame(width: 16, height: 16), "Splits the ball in three")
            rule(blasterMark.frame(width: 16, height: 16), "Shoots from the paddle for 5 seconds")
            rule(lineMark, "Clears its row, or its column")
            rule(bombMark.frame(width: 16, height: 16), "Clears every square on the screen")
        }
    }

    private var blasterMark: some View {
        ZStack {
            Rectangle().strokeBorder(colors.accent, lineWidth: 1.5)
            Rectangle().fill(colors.accent).padding(3)
        }
    }

    private var lineMark: some View {
        HStack(spacing: 4) {
            ZStack {
                ChamferShape().fill(colors.ink)
                Rectangle().fill(colors.background).frame(width: 7, height: 1.5)
            }
            .frame(width: 16, height: 16)
            ZStack {
                ChamferShape().fill(colors.ink)
                Rectangle().fill(colors.background).frame(width: 1.5, height: 7)
            }
            .frame(width: 16, height: 16)
        }
    }

    private var bombMark: some View {
        ZStack {
            Circle().fill(colors.ink)
            Circle().fill(colors.accent).padding(5)
        }
    }

    private func rule(_ mark: some View, _ text: String) -> some View {
        HStack(spacing: 12) {
            mark.frame(width: 36, height: 16, alignment: .leading)
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
