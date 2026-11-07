import SwiftUI

/// Hue: a board of colours blending from corner to corner, shuffled. Swap squares until every
/// colour is back in its place. Squares with a dot are fixed. Fifty levels, easy to very hard.
@MainActor
@Observable
final class HueGame {
    enum Phase { case ready, preview, playing, paused, solved }

    struct Tile {
        let id: Int              // which colour it is (its home place)
        var x: Double            // where it's drawn, in cells
        var y: Double
        var lift: Double = 0     // raised while dragged or picked
    }

    private(set) var phase: Phase = .ready
    private(set) var number = 1          // level 1...10
    private(set) var swaps = 0
    private(set) var frame = 0
    private(set) var newBest = false
    /// The level picked on the landing page.
    var chosen = 1

    @ObservationIgnored private(set) var colors: [RGB] = []
    @ObservationIgnored private(set) var order: [Int] = []      // order[place] = tile id there
    @ObservationIgnored private(set) var tiles: [Tile] = []     // by id
    @ObservationIgnored private(set) var level = HueLevels.all[0]
    @ObservationIgnored private(set) var picked: Int?            // place picked by a tap
    @ObservationIgnored private(set) var dragging: (place: Int, point: CGPoint)?
    /// Seconds since solving, for the wave across the board.
    @ObservationIgnored private(set) var solvedAge: Double = 0
    @ObservationIgnored private(set) var clock: Double = 0
    @ObservationIgnored private var previewLeft: Double = 0

    let cols = HueLevels.cols
    let rows = HueLevels.rows
    let coach = Coach()
    private let ticker = FrameTicker()

    init() {
        ticker.onTick = { [weak self] dt in
            MainActor.assumeIsolated { self?.tick(dt) }
        }
    }

    func isFixed(_ place: Int) -> Bool { HueLevels.isFixed(level, place) }

    /// Tutorial: a square that's out of place, and the place it belongs (swapping fixes it).
    var guide: (from: Int, to: Int)? {
        guard coach.current?.waitFor == .swap, phase == .playing else { return nil }
        for p in order.indices where !isRight(p) {
            let home = order[p]
            if !isFixed(home) && home != p { return (p, home) }
        }
        return nil
    }

    // MARK: Phases

    /// Show the finished board for a moment, then shuffle it.
    func start(_ n: Int? = nil) {
        number = max(1, min(HueLevels.count, n ?? chosen))
        chosen = number
        level = HueLevels.all[number - 1]
        let s = Settings.shared
        colors = HueLevels.colors(level, accent: s.look.accent, second: s.secondAccent)
        order = Array(0..<(cols * rows))
        tiles = (0..<(cols * rows)).map { Tile(id: $0, x: Double($0 % cols), y: Double($0 / cols)) }
        swaps = 0; newBest = false; picked = nil; dragging = nil; solvedAge = 0
        previewLeft = 1.6
        phase = .preview
        ticker.start()
    }

    func pause() { if phase == .playing { phase = .paused } }
    func resume() { if phase == .paused { phase = .playing } }

    func home() {
        phase = .ready
        ticker.stop()
    }

    func next() {
        start(min(HueLevels.count, number + 1))
    }

    private func shuffleIn() {
        order = HueLevels.shuffle(level, number: number)
        phase = .playing
        Haptics.tap(.medium)
        coach.begin("hue", steps: [
            .init(text: "The colours were in order a moment ago.\nThey blend smoothly from corner to corner.\nSquares with a dot never move.",
                  waitFor: .tapToContinue, picture: .hueFixed),
            .init(text: "Drag the outlined square\nonto the other one to swap them.", waitFor: .swap),
            .init(text: "Or tap one square, then another.\nTry it.", waitFor: .swap),
            .init(text: "Keep swapping until every colour\nis back in its place.", waitFor: .tapToContinue),
        ])
    }

    // MARK: Swapping

    /// Drag a square: it lifts and follows the finger.
    func drag(from place: Int, to point: CGPoint) {
        guard phase == .playing, !isFixed(place) else { return }
        if dragging == nil { Haptics.tap(.light, intensity: 0.5); picked = nil }
        dragging = (place, point)
    }

    /// Let go over another square: swap the two.
    func drop(on place: Int?) {
        guard let d = dragging else { return }
        dragging = nil
        if let p = place, p != d.place, !isFixed(p) { swap(d.place, p) }
    }

    /// Tap one square, then another, to swap them.
    func tap(_ place: Int) {
        guard phase == .playing, !isFixed(place) else {
            if phase == .playing { Haptics.tap(.soft, intensity: 0.3) }
            return
        }
        if let p = picked {
            picked = nil
            if p != place { swap(p, place) }
        } else {
            picked = place
            Haptics.tap(.light, intensity: 0.5)
        }
    }

    private func swap(_ a: Int, _ b: Int) {
        order.swapAt(a, b)
        swaps += 1
        coach.did(.swap)
        let right = (isRight(a) ? 1 : 0) + (isRight(b) ? 1 : 0)
        Haptics.tap(right > 0 ? .rigid : .light, intensity: right > 0 ? 0.8 : 0.5)
        if order.indices.allSatisfy(isRight) { solved() }
    }

    /// The colour at this place is the one that belongs there (two squares can share a colour).
    func isRight(_ place: Int) -> Bool {
        let a = colors[order[place]], b = colors[place]
        return abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) < 0.006
    }

    private func solved() {
        phase = .solved
        solvedAge = 0
        let s = Settings.shared
        let key = String(number)
        if swaps < (s.hueBest[key] ?? .max) { s.hueBest[key] = swaps; newBest = true }
        if number > s.hueSolved { s.hueSolved = number }
        chosen = min(HueLevels.count, number + 1)
        Haptics.notify(.success)
    }

    // MARK: Loop

    private func tick(_ dt: Double) {
        guard phase != .ready, phase != .paused else { return }
        clock += dt
        if phase == .preview {
            previewLeft -= dt
            if previewLeft <= 0 { shuffleIn() }
        }
        if phase == .solved { solvedAge += dt }
        // Every square slides towards its place.
        for place in order.indices {
            let id = order[place]
            var t = tiles[id]
            let tx = Double(place % cols), ty = Double(place / cols)
            let k = min(1, dt * 14)
            t.x += (tx - t.x) * k
            t.y += (ty - t.y) * k
            let lifted = dragging?.place == place || picked == place
            t.lift += ((lifted ? 1 : 0) - t.lift) * min(1, dt * 16)
            tiles[id] = t
        }
        frame &+= 1
    }
}
