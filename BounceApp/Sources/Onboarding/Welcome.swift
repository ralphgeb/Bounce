import SwiftUI

/// The first launch: the Bricks logo with squares dropping into place, then picking the look that
/// stays free. Shown once.
struct WelcomeView: View {
    let onDone: () -> Void

    @State private var settings = Settings.shared
    @State private var page = 0
    @State private var dropped = false
    @State private var drag: CGSize = .zero
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let c = settings.colors(scheme)
        ZStack {
            c.background.ignoresSafeArea()
            if page == 0 { intro(c).transition(.opacity) } else { picker(c).transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.35), value: page)
        .animation(.easeInOut(duration: 0.3), value: settings.lookID)
        .elasticDrag($drag)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55)) { dropped = true }
        }
    }

    // MARK: Page 1: Bricks

    private func intro(_ c: Colors) -> some View {
        VStack(spacing: 0) {
            Spacer()
            ElasticLogo(word: "BRICKS",
                        fills: [c.ink, c.accent, c.ink.opacity(0.72), c.ink.opacity(0.48), c.ink.opacity(0.28), c.ink.opacity(0.12)],
                        ink: c.ink, drag: drag, dropped: dropped)
            Text("Four small games.\nSimple to learn, hard to put down.")
                .font(.system(size: 15))
                .lineSpacing(4)
                .multilineTextAlignment(.center)
                .foregroundStyle(c.ink.opacity(0.55))
                .padding(.top, 34)
            // The four games, in their own shapes.
            HStack(spacing: 22) {
                gameMark(c, "Bounce") { Rectangle().fill(c.accent).frame(width: 14, height: 14) }
                gameMark(c, "Maze") { StarShape().fill(c.accent).frame(width: 16, height: 16) }
                gameMark(c, "Switch") { Rectangle().fill(c.accent).frame(width: 11, height: 11).rotationEffect(.degrees(45)) }
                gameMark(c, "Hue") {
                    HStack(spacing: 2) { ForEach(Array(HueColor.logo(c.accent).enumerated()), id: \.offset) { _, x in Rectangle().fill(x).frame(width: 5, height: 14) } }
                }
            }
            .padding(.top, 34)
            Spacer()
            Spacer()
            OutlineButton(title: "Next", colors: c) { page = 1 }
                .padding(.bottom, 64)
        }
    }

    private func gameMark<Mark: View>(_ c: Colors, _ name: String, @ViewBuilder mark: () -> Mark) -> some View {
        VStack(spacing: 10) {
            mark().frame(height: 18)
            Text(name.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(c.ink.opacity(0.5))
        }
    }

    // MARK: Page 2: your look

    private func picker(_ c: Colors) -> some View {
        VStack(spacing: 0) {
            Spacer()
            Text("Choose your look")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(c.ink)
            Text("This one is yours for free.\nThe others come with Unlock everything.")
                .font(.system(size: 14))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .foregroundStyle(c.ink.opacity(0.55))
                .padding(.top, 10)
            // The five looks as big 3 × 3 grids.
            let grid = [GridItem(.fixed(96), spacing: 18), GridItem(.fixed(96), spacing: 18), GridItem(.fixed(96), spacing: 18)]
            LazyVGrid(columns: grid, spacing: 22) {
                ForEach(Look.all) { look in
                    let chosen = settings.lookID == look.id
                    Button {
                        // Picking here sets the free look too, so the page shows it straight away.
                        settings.lookID = look.id
                        settings.freeLook = look.id
                        Haptics.tap(.light)
                    } label: {
                        VStack(spacing: 9) {
                            LookSwatch(look: look, dark: scheme == .dark)
                                .frame(width: 72, height: 72)
                                .padding(7)
                                .overlay(Rectangle().strokeBorder(c.ink, lineWidth: 1.5).opacity(chosen ? 1 : 0))
                            Text(look.name)
                                .font(.system(size: 12, weight: chosen ? .semibold : .regular))
                                .foregroundStyle(c.ink.opacity(chosen ? 0.9 : 0.5))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(look.name)
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
            .padding(.top, 36)
            Spacer()
            Spacer()
            OutlineButton(title: "Start", colors: c) {
                settings.freeLook = settings.lookID
                settings.onboarded = true
                onDone()
            }
            .padding(.bottom, 64)
        }
    }
}
