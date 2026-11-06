import SwiftUI

enum Screen { case menu, bounce, maze }

/// The main menu: one panel per game. Bounce in the chosen look, Maze always in the dark
/// with its light sweeping round.
struct MenuView: View {
    let colors: Colors
    let dark: Colors
    let open: (Screen) -> Void
    @Binding var showSettings: Bool

    @State private var drag: CGSize = .zero
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Games").bounceLabel(colors)
                Spacer()
                Button { showSettings = true } label: {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 17))
                        .foregroundStyle(colors.ink.opacity(0.45))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Settings")
            }
            .padding(.leading, 6)

            panel(index: 0) { bouncePanel }
            panel(index: 1) { mazePanel }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .elasticDrag($drag)
        .onAppear {
            appeared = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8)) { appeared = true }
        }
    }

    private func panel<Content: View>(index: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(Rectangle())
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 30)
            .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.8).delay(Double(index) * 0.08), value: appeared)
    }

    // MARK: Bounce

    private var bouncePanel: some View {
        Button {
            Haptics.tap(.medium)
            open(.bounce)
        } label: {
            ZStack {
                colors.ink.opacity(0.045)
                BounceBackdrop(colors: colors)
                VStack(spacing: 0) {
                    Spacer()
                    ElasticLogo(word: "BOUNCE",
                                fills: [colors.ink, colors.accent, colors.ink.opacity(0.72), colors.ink.opacity(0.48), colors.ink.opacity(0.28), colors.ink.opacity(0.12)],
                                ink: colors.ink, squareSize: 24, letterSize: 20, drag: drag)
                    Spacer()
                    footer(colors, "Break the wall that never ends",
                           Settings.shared.best > 0 ? "Best \(Settings.shared.best)" : "Play")
                }
            }
        }
        .buttonStyle(PanelPress())
        .accessibilityLabel("Bounce. Break the wall that never ends")
    }

    // MARK: Maze

    private var mazePanel: some View {
        Button {
            Haptics.tap(.medium)
            open(.maze)
        } label: {
            ZStack {
                MazePreview(colors: dark, tilesAcross: 12, strength: 0.9)
                LinearGradient(colors: [dark.background.opacity(0), dark.background.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                VStack(spacing: 0) {
                    Spacer()
                    ElasticLogo(word: "MAZE", fills: [dark.ink, dark.accent, dark.ink.opacity(0.5), dark.ink.opacity(0.22)],
                                ink: dark.ink, squareSize: 24, letterSize: 20, drag: drag)
                    Spacer()
                    footer(dark, "Find your way in the dark",
                           Settings.shared.mazeDeepest > 1 ? "Deepest level \(Settings.shared.mazeDeepest)" : "Play")
                }
            }
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(PanelPress())
        .accessibilityLabel("Maze. Find your way in the dark")
    }

    private func footer(_ c: Colors, _ line: String, _ right: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(line)
                .font(.system(size: 13))
                .foregroundStyle(c.ink.opacity(0.6))
            Spacer()
            Text(right.uppercased())
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .tracking(1.4)
                .foregroundStyle(c.ink)
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c.accent)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }
}

private struct PanelPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Behind the Bounce panel: a few rows of squares drifting down, and the ball going back and forth.
private struct BounceBackdrop: View {
    let colors: Colors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let shades: [Double] = {
        var rng = SeededRandom(seed: 42)
        return (0..<90).map { _ in
            let r = Double(rng.next() % 100) / 100
            return r < 0.22 ? 0 : r < 0.3 ? -1 : r < 0.55 ? 0.16 : r < 0.8 ? 0.38 : 0.7
        }
    }()

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            Canvas { ctx, size in
                let t = reduceMotion ? 0 : tl.date.timeIntervalSinceReferenceDate
                let cols = 9, gap: CGFloat = 4, side: CGFloat = 16
                let cell = (size.width - side * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)
                let rowH = cell + gap
                let rows = 10
                let drift = CGFloat((t * 6).truncatingRemainder(dividingBy: Double(rowH)))
                for r in 0..<rows {
                    let y = CGFloat(r - 1) * rowH + drift - rowH * 2
                    let fade = max(0, 1 - Double(y) / Double(size.height * 0.45))
                    for c in 0..<cols {
                        let shade = Self.shades[(r * cols + c) % Self.shades.count]
                        guard shade != 0 else { continue }
                        let rect = CGRect(x: side + CGFloat(c) * rowH, y: y, width: cell, height: cell)
                        let color = shade < 0 ? colors.accent : colors.ink.opacity(shade)
                        ctx.fill(Path(rect), with: .color(color.opacity(fade)))
                    }
                }
                // The paddle and the ball, bouncing between the two.
                let pw = size.width * 0.22
                let px = size.width / 2 + sin(t * 0.9) * size.width * 0.25
                let py = size.height - 54
                ctx.fill(Path(roundedRect: CGRect(x: px - pw / 2, y: py, width: pw, height: 7), cornerRadius: 3.5),
                         with: .color(colors.ink.opacity(0.55)))
                let phase = (t * 0.7).truncatingRemainder(dividingBy: 1)
                let by = py - 8 - CGFloat(4 * phase * (1 - phase)) * size.height * 0.35
                let bx = px + CGFloat(sin(t * 1.7)) * 20
                ctx.fill(Path(ellipseIn: CGRect(x: bx - 5, y: by - 5, width: 10, height: 10)), with: .color(colors.accent))
            }
        }
        .allowsHitTesting(false)
    }
}
