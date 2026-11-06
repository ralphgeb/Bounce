import SwiftUI

@main
struct BounceApp: App {
    @State private var settings = Settings.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(settings.mode.colorScheme)
        }
    }
}

/// The landing page and the game share one screen: the game draws behind, the landing sits on top.
struct RootView: View {
    @State private var game = Game()
    @State private var settings = Settings.shared
    @State private var showSettings = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let c = settings.colors(scheme)
        GeometryReader { geo in
            ZStack {
                c.background.ignoresSafeArea()

                if game.phase == .playing || game.phase == .paused {
                    GameView(game: game, colors: c, safeTop: geo.safeAreaInsets.top, safeBottom: geo.safeAreaInsets.bottom)
                        .transition(.opacity)
                } else {
                    HomeView(game: game, colors: c, showSettings: $showSettings)
                        .transition(.opacity)
                }
            }
            .onAppear { layout(geo) }
            .onChange(of: geo.size) { layout(geo) }
        }
        .animation(.easeInOut(duration: 0.25), value: game.phase)
        .statusBarHidden(game.phase == .playing || game.phase == .paused)
        .persistentSystemOverlays(game.phase == .playing ? .hidden : .automatic)
        .defersSystemGestures(on: .bottom)
        .sheet(isPresented: $showSettings) {
            SettingsView(colors: c)
                .presentationDragIndicator(.visible)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.pause() }
        }
    }

    private func layout(_ geo: GeometryProxy) {
        // The canvas fills the whole screen, so add the safe area back to the size.
        let i = geo.safeAreaInsets
        let full = CGSize(width: geo.size.width + i.leading + i.trailing, height: geo.size.height + i.top + i.bottom)
        game.layout(size: full, safeTop: i.top, safeBottom: i.bottom)
    }
}
