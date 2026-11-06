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

/// The menu, and each game's landing page and board. Every game follows the look's light or dark.
struct RootView: View {
    @State private var screen: Screen = .menu
    @State private var game = Game()
    @State private var maze = MazeGame()
    @State private var switcher = SwitchGame()
    @State private var settings = Settings.shared
    @State private var showSettings = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase

    private var playing: Bool {
        switch screen {
        case .bounce: return game.phase == .playing || game.phase == .paused
        case .maze: return maze.phase != .ready
        case .switcher: return switcher.phase != .ready
        case .menu: return false
        }
    }

    var body: some View {
        let c = settings.colors(scheme)
        // Maze is pitch black in dark mode and pitch white in light mode.
        let mazeColors = Colors(ink: c.ink, background: scheme == .dark ? .black : .white, accent: c.accent)
        GeometryReader { geo in
            ZStack {
                (screen == .maze ? mazeColors.background : c.background).ignoresSafeArea()

                switch screen {
                case .menu:
                    MenuView(colors: c, open: { s in screen = s }, showSettings: $showSettings)
                        .transition(.opacity)
                case .bounce:
                    Group {
                        if game.phase == .playing || game.phase == .paused {
                            GameView(game: game, colors: c, safeTop: geo.safeAreaInsets.top, safeBottom: geo.safeAreaInsets.bottom)
                        } else {
                            HomeView(game: game, colors: c, onBack: { screen = .menu }, onSettings: { showSettings = true })
                        }
                    }
                    .transition(.opacity)
                case .maze:
                    Group {
                        if maze.phase == .ready {
                            MazeHome(game: maze, colors: mazeColors, onBack: { screen = .menu }, onSettings: { showSettings = true })
                        } else {
                            MazeView(game: maze, colors: mazeColors)
                        }
                    }
                    .transition(.opacity)
                case .switcher:
                    Group {
                        if switcher.phase == .ready {
                            SwitchHome(game: switcher, colors: c, onBack: { screen = .menu }, onSettings: { showSettings = true })
                        } else {
                            SwitchView(game: switcher, colors: c)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .onAppear { layout(geo) }
            .onChange(of: geo.size) { layout(geo) }
        }
        .animation(.easeInOut(duration: 0.3), value: screen)
        .animation(.easeInOut(duration: 0.25), value: game.phase)
        .animation(.easeInOut(duration: 0.3), value: maze.phase == .ready)
        .animation(.easeInOut(duration: 0.3), value: switcher.phase == .ready)
        .statusBarHidden(playing)
        .persistentSystemOverlays(playing ? .hidden : .automatic)
        .defersSystemGestures(on: .bottom)
        .sheet(isPresented: $showSettings) {
            SettingsView(colors: c)
                .presentationDragIndicator(.visible)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.pause(); maze.pause(); switcher.pause() }
        }
    }

    private func layout(_ geo: GeometryProxy) {
        // Bounce's canvas fills the whole screen, so add the safe area back to the size.
        let i = geo.safeAreaInsets
        let full = CGSize(width: geo.size.width + i.leading + i.trailing, height: geo.size.height + i.top + i.bottom)
        game.layout(size: full, safeTop: i.top, safeBottom: i.bottom)
    }
}
