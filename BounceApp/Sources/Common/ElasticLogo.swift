import SwiftUI
import QuartzCore

/// A row of squares over the letters of a game's name. Drag anywhere on the page and the squares
/// stretch after your finger, each on its own spring, then bounce back into place when you let go.
struct ElasticLogo: View {
    let word: String
    let fills: [Color]
    let ink: Color
    var squareSize: CGFloat = 34
    var letterSize: CGFloat = 28
    /// How far the finger has moved (zero when not touching).
    var drag: CGSize = .zero
    /// False before the squares drop in.
    var dropped: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var letters: [String] { word.map { String($0) } }

    var body: some View {
        let n = letters.count
        HStack(spacing: squareSize * 0.3) {
            ForEach(0..<n, id: \.self) { i in
                VStack(spacing: squareSize * 0.53) {
                    Rectangle()
                        .fill(fills[i % fills.count])
                        .frame(width: squareSize, height: squareSize)
                        .rotationEffect(.degrees(reduceMotion ? 0 : tilt(i, of: n)))
                        .offset(reduceMotion ? .zero : pull(i, of: n, strength: 1))
                        .animation(.spring(response: 0.32 + 0.05 * Double(i), dampingFraction: 0.42), value: drag)
                        .offset(y: dropped ? 0 : -80)
                        .opacity(dropped ? 1 : 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.55).delay(Double(i) * 0.07), value: dropped)
                    Text(letters[i])
                        .font(.system(size: letterSize, weight: .bold))
                        .foregroundStyle(ink)
                        .offset(reduceMotion ? .zero : pull(i, of: n, strength: 0.28))
                        .animation(.spring(response: 0.4 + 0.04 * Double(i), dampingFraction: 0.5), value: drag)
                }
                .frame(width: squareSize * 1.18)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(word.capitalized)
        .accessibilityAddTraits(.isHeader)
    }

    /// Each square follows the finger by a different amount, with a rubber band so it never flies off.
    private func pull(_ i: Int, of n: Int, strength: CGFloat) -> CGSize {
        let f = (0.22 + 0.1 * sin(Double(i) * 1.9 + 0.6)) * strength
        func band(_ v: CGFloat, _ limit: CGFloat) -> CGFloat { limit * CGFloat(tanh(Double(v) * f / Double(limit))) }
        return CGSize(width: band(drag.width, 46), height: band(drag.height, 40))
    }

    /// A small lean away from the middle as the row stretches sideways.
    private func tilt(_ i: Int, of n: Int) -> Double {
        let mid = Double(n - 1) / 2
        let side = (Double(i) - mid) / max(mid, 1)
        return max(-14, min(14, Double(drag.width) * 0.06 * (0.6 + 0.4 * side) + Double(drag.height) * 0.03 * side))
    }
}

/// Drives an ElasticLogo from a drag anywhere on the page, without getting in the way of buttons.
struct ElasticDrag: ViewModifier {
    @Binding var drag: CGSize

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { drag = $0.translation }
                    .onEnded { v in
                        // Let go of a good stretch: a soft spring.
                        let pull = hypot(v.translation.width, v.translation.height)
                        if pull > 24 { Sound.shared.play("spring", volume: Float(min(1, pull / 160)), gap: 0.2) }
                        drag = .zero
                    }
            )
    }
}

extension View {
    func elasticDrag(_ drag: Binding<CGSize>) -> some View { modifier(ElasticDrag(drag: drag)) }
}

/// The page header: a back chevron on the left, and the settings button on the right.
struct BackBar: View {
    let ink: Color
    var settings: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        HStack {
            Button {
                Haptics.tap(.light)
                Sound.shared.play("back")
                action()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(ink.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Games")
            Spacer()
            if let settings {
                Button {
                    Sound.shared.play("tap")
                    settings()
                } label: {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 17))
                        .foregroundStyle(ink.opacity(0.45))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Settings")
            }
        }
        .padding(.horizontal, 8)
    }
}

/// Calls back on every screen refresh with the time since the last one.
final class FrameTicker: NSObject {
    private var link: CADisplayLink?
    private var last: CFTimeInterval = 0
    var onTick: ((Double) -> Void)?

    func start() {
        guard link == nil else { return }
        last = 0
        let l = CADisplayLink(target: self, selector: #selector(step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ l: CADisplayLink) {
        let t = l.targetTimestamp
        let dt = last == 0 ? 1.0 / 60 : min(1.0 / 30, t - last)
        last = t
        onTick?(dt)
    }
}
