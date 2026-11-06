import SwiftUI

/// The landing page for Bounce (six squares over B O U N C E) and Hide (four over H I D E):
/// the special squares, and Start.
struct HomeView: View {
    let game: Game
    let colors: Colors
    let onBack: () -> Void
    let onSettings: () -> Void

    @State private var dropped = false
    @State private var drag: CGSize = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            BackBar(ink: colors.ink, settings: onSettings, action: onBack)

            Spacer()
            ElasticLogo(word: game.hide ? "HIDE" : "BOUNCE", fills: logoFills, ink: colors.ink, drag: drag, dropped: dropped)
            rules.padding(.top, 34)
            // The last score sits a third of the way from the rules down to the button.
            Spacer(minLength: 16)
            Text(result)
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(colors.ink.opacity(0.5))
                .frame(minHeight: 20)
            Spacer(minLength: 16)
            Spacer(minLength: 16)
            // Low on the screen, where the thumb is.
            OutlineButton(title: game.phase == .over ? "Again" : "Start", colors: colors) { game.start() }
                .padding(.bottom, 64)
        }
        .elasticDrag($drag)
        .onAppear {
            dropped = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55)) { dropped = true }
        }
    }

    /// Bounce: the main colour, the accent over the O, then lighter shades. Hide: mostly in the dark.
    private var logoFills: [Color] {
        game.hide
            ? [colors.ink.opacity(0.12), colors.ink.opacity(0.45), colors.accent, colors.ink.opacity(0.2)]
            : [colors.ink, colors.accent, colors.ink.opacity(0.72), colors.ink.opacity(0.48), colors.ink.opacity(0.28), colors.ink.opacity(0.12)]
    }

    /// The special squares, drawn as they look in the game.
    private var rules: some View {
        VStack(alignment: .leading, spacing: 12) {
            if game.hide {
                rule(glowMark.frame(width: 16, height: 16), "The ball is your light. Clear the board in the dark")
                rule(flareMark.frame(width: 16, height: 16), "Lights up every square for 3 seconds")
            }
            rule(Rectangle().fill(colors.accent).frame(width: 16, height: 16), "Splits the ball in three")
            rule(lineMark(across: true).frame(width: 16, height: 16), "Clears its row")
            rule(lineMark(across: false).frame(width: 16, height: 16), "Clears its column")
            rule(blasterMark.frame(width: 16, height: 16), "Shoots from the paddle for 3 seconds")
            rule(bombMark.frame(width: 16, height: 16), "Clears every square on the screen")
        }
    }

    private var glowMark: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [colors.ink.opacity(0.7), colors.ink.opacity(0)], center: .center, startRadius: 0, endRadius: 9))
            Circle().fill(colors.accent).frame(width: 6, height: 6)
        }
    }

    private var flareMark: some View {
        ZStack {
            Circle().strokeBorder(colors.accent, lineWidth: 2)
            Circle().fill(colors.accent).frame(width: 4, height: 4)
        }
    }

    private var blasterMark: some View {
        ZStack {
            Rectangle().strokeBorder(colors.accent, lineWidth: 1.5)
            Rectangle().fill(colors.accent).padding(3)
        }
    }

    private func lineMark(across: Bool) -> some View {
        ZStack {
            ChamferShape().fill(colors.accent)
            Rectangle().fill(colors.background).frame(width: across ? 7 : 1.5, height: across ? 1.5 : 7)
        }
    }

    private var bombMark: some View {
        Circle().fill(colors.accent)
    }

    private func rule(_ mark: some View, _ text: String) -> some View {
        HStack(spacing: 12) {
            mark.frame(width: 36, height: 16, alignment: .leading)
            Text(text).font(.system(size: 13)).foregroundStyle(colors.ink.opacity(0.6))
        }
    }

    private var result: String {
        let s = Settings.shared
        let best = game.hide ? s.hideBest : s.best
        guard game.phase == .over else { return best > 0 ? "Best \(best)" : " " }
        if game.hide {
            return game.newBest ? "New best · \(game.score) · level \(game.level)" : "\(game.score) · level \(game.level) · best \(best)"
        }
        if game.newBest { return "New best · \(game.score) · \(formatTime(game.elapsed))" }
        return "\(game.score) · \(formatTime(game.elapsed)) · best \(best)"
    }
}
