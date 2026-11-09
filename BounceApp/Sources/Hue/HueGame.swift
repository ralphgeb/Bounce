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
    /// Set when a locked level is wanted: offer Unlock everything.
    var askUnlock = false
    /// Playing the tutorial's one-row board (the first time only).
    private(set) var inTutorial = false
    /// The fewest swaps that solve this board, and the stars won (1 to 3).
    private(set) var fewestSwaps = 0
    private(set) var stars = 0

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

    /// The board's size: small on the first levels, 7 × 8 from level 5.
    var cols: Int { level.cols }
    var rows: Int { level.rows }
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
        number = max(1, min(Unlock.shared.isUnlocked ? HueLevels.count : Unlock.freeLevels, n ?? chosen))
        chosen = number
        // The first time, a one-row tutorial board comes before the real level.
        inTutorial = !Coach.seen("hue")
        level = inTutorial ? HueLevels.tutorial : HueLevels.all[number - 1]
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
        let n = min(HueLevels.count, number + 1)
        // Levels past the free ones need Unlock everything.
        if n > Unlock.freeLevels && !Unlock.shared.isUnlocked { askUnlock = true; return }
        start(n)
    }

    private func shuffleIn() {
        order = inTutorial ? HueLevels.tutorialOrder : HueLevels.shuffle(level, number: number)
        // Each loop of k squares out of place takes k − 1 swaps.
        var visited = Set<Int>()
        fewestSwaps = 0
        for start in order.indices where !visited.contains(start) && order[start] != start {
            var i = start, length = 0
            while !visited.contains(i) { visited.insert(i); i = order[i]; length += 1 }
            fewestSwaps += length - 1
        }
        phase = .playing
        Haptics.tap(.medium)
        Sound.shared.play("whoosh", volume: 0.55)
        coach.begin("hue", steps: [
            .init(text: "Put the colours back in order.\nThey run smoothly from one end to the other.\nSquares with a dot never move.",
                  waitFor: .tapToContinue, inline: true),
            .init(text: "Drag the outlined square\nonto the other one to swap them.", waitFor: .swap),
            .init(text: "One more.\nYou can also tap one square, then the other.", waitFor: .swap),
            .init(text: "Solved: every colour is in its place.\nEach level is a bigger board.", waitFor: .tapToContinue, inline: true),
        ], onFinish: { [weak self] in self?.endTutorial() })
    }

    /// Tutorial done (or skipped): on to the real level.
    private func endTutorial() {
        guard inTutorial else { return }
        start(chosen)
    }

    // MARK: Swapping

    /// Drag a square: it lifts and follows the finger.
    func drag(from place: Int, to point: CGPoint) {
        guard phase == .playing, !isFixed(place) else { return }
        if dragging == nil { Haptics.tap(.light, intensity: 0.5); Sound.shared.play("tick", volume: 0.7); picked = nil }
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
            if phase == .playing { Haptics.tap(.soft, intensity: 0.3); Sound.shared.play("bump", volume: 0.3, gap: 0.15) }
            return
        }
        if let p = picked {
            picked = nil
            if p != place { swap(p, place) }
        } else {
            picked = place
            Haptics.tap(.light, intensity: 0.5)
            Sound.shared.play("tick", volume: 0.7)
        }
    }

    private func swap(_ a: Int, _ b: Int) {
        order.swapAt(a, b)
        swaps += 1
        coach.did(.swap)
        let right = (isRight(a) ? 1 : 0) + (isRight(b) ? 1 : 0)
        Haptics.tap(right > 0 ? .rigid : .light, intensity: right > 0 ? 0.8 : 0.5)
        // The same soft swap as Switch; and a quiet note when a colour lands home, a little higher
        // as the board fills in.
        Sound.shared.play("swish_soft", volume: 0.7)
        if right > 0 {
            let done = Double(order.indices.filter(isRight).count) / Double(max(1, order.count))
            Sound.shared.note(3 + Int(done * 6), volume: 0.35)
        }
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
        if inTutorial { Haptics.notify(.success); Sound.shared.play("win"); return }
        let s = Settings.shared
        let key = String(number)
        // Stars: three for the fewest swaps, two for a few more, one otherwise.
        stars = swaps <= fewestSwaps ? 3 : swaps <= fewestSwaps + max(3, fewestSwaps / 4) ? 2 : 1
        if stars > (s.hueStars[key] ?? 0) { s.hueStars[key] = stars }
        if swaps < (s.hueBest[key] ?? .max) { s.hueBest[key] = swaps; newBest = true }
        if number > s.hueSolved { s.hueSolved = number }
        chosen = min(HueLevels.count, number + 1)
        Haptics.notify(.success)
        Sound.shared.play("win")
        let won = stars
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            Sound.shared.bells(Array([6, 8, 10].prefix(won)), every: 0.22)
        }
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
