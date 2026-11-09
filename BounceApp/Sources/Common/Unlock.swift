import StoreKit
import SwiftUI

/// "Unlock everything": one payment through the App Store (StoreKit 2). Every game can be played
/// without it; it opens Maze and Hue past level 2, every look (one, picked at the start, is free),
/// and keeps your best scores in Bounce and Switch. In TestFlight the purchase happens in Apple's
/// sandbox, so nothing is charged.
///
/// For trying it out, Settings has two switches: Apply paywall (off = everything open, as if bought)
/// and Reset purchase (locks the games again on this iPhone until you buy or restore again).
@MainActor
@Observable
final class Unlock {
    static let shared = Unlock()
    static let productID = "com.ralphgeb.bounce.unlock"
    /// Maze and Hue levels you can play without unlocking.
    static let freeLevels = 2
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private let defaults = UserDefaults.standard

    private(set) var product: Product?
    private(set) var owned: Bool { didSet { defaults.set(owned, forKey: "unlock.owned") } }
    /// Settings › Apply paywall. Off: every game open.
    var paywallOn: Bool { didSet { defaults.set(paywallOn, forKey: "unlock.paywall") } }
    /// Settings › Reset purchase: act as if not bought, until bought or restored again.
    private(set) var reset: Bool { didSet { defaults.set(reset, forKey: "unlock.reset") } }
    private(set) var busy = false
    private(set) var message: String?

    @ObservationIgnored private var updates: Task<Void, Never>?

    /// Everything open: bought (and not reset for testing), or the paywall switched off.
    var isUnlocked: Bool { !paywallOn || (owned && !reset) }

    /// Before the App Store answers: "£1.99" in the UK, "$1.99" elsewhere.
    var price: String {
        if let product { return product.displayPrice }
        return Locale.current.currency?.identifier == "GBP" ? "£1.99" : "$1.99"
    }

    private init() {
        owned = defaults.bool(forKey: "unlock.owned")
        paywallOn = defaults.object(forKey: "unlock.paywall") as? Bool ?? true
        reset = defaults.bool(forKey: "unlock.reset")
        updates = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let t) = result { await t.finish() }
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        if product == nil { product = try? await Product.products(for: [Self.productID]).first }
        var has = false
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let t) = result, t.productID == Self.productID, t.revocationDate == nil { has = true }
        }
        owned = has
    }

    /// Apple's payment sheet. True once everything is unlocked.
    func buy() async -> Bool {
        message = nil
        if product == nil { await refresh() }
        guard let product else {
            message = "The App Store isn't answering right now. Please try again in a moment."
            return false
        }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let t) = verification {
                    await t.finish()
                    owned = true
                    reset = false
                    return true
                }
            case .pending:
                message = "Your purchase is waiting for approval."
            default:
                break
            }
        } catch {
            message = error.localizedDescription
        }
        return false
    }

    /// Restore purchases: asks the App Store for this Apple account's purchases.
    func restore() async {
        message = nil
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
        if owned { reset = false } else { message = "No earlier purchase was found for this Apple account." }
    }

    /// For trying the paywall again: lock the games on this iPhone (the App Store purchase stays).
    func resetPurchase() {
        reset = true
        message = nil
    }
}

/// The unlock sheet: the three games it opens, the price, Apple's payment sheet, then a welcome.
struct UnlockSheet: View {
    let colors: Colors
    @Environment(\.dismiss) private var dismiss
    @State private var unlock = Unlock.shared
    @State private var done = false
    @State private var height: CGFloat = 520

    var body: some View {
        VStack(spacing: 0) {
            if done { welcome.transition(.opacity.combined(with: .scale(scale: 0.96))) } else { offer.transition(.opacity) }
        }
        .padding(.horizontal, 26)
        .padding(.top, 34)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in Color.clear.preference(key: UnlockHeightKey.self, value: g.size.height) })
        .onPreferenceChange(UnlockHeightKey.self) { h in if h > 0 { height = h } }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(colors.background.ignoresSafeArea())
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .animation(.smooth(duration: 0.35), value: done)
        .interactiveDismissDisabled(unlock.busy)
        .task { await unlock.refresh() }
    }

    private var offer: some View {
        VStack(spacing: 22) {
            VStack(spacing: 6) {
                Text("Unlock everything")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(colors.ink)
                Text("One payment, yours for good.")
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(colors.ink.opacity(0.55))
            }
            VStack(alignment: .leading, spacing: 14) {
                perk(StarShape().fill(colors.accent).frame(width: 14, height: 14), "Maze", "All 40 levels in the dark")
                perk(hue, "Hue", "All 50 colour puzzles")
                perk(Rectangle().fill(colors.accent).frame(width: 12, height: 12), "Best scores", "Kept in Bounce and Switch")
                perk(looks, "Every look", "All six colour themes and their icons")
            }
            VStack(spacing: 10) {
                Button {
                    Task { if await unlock.buy() { Sound.shared.play("win"); withAnimation { done = true } } }
                } label: {
                    ZStack {
                        if unlock.busy { ProgressView().tint(colors.background) } else { Text("Unlock · \(unlock.price)") }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(0.6)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(colors.ink)
                    .foregroundStyle(colors.background)
                }
                .disabled(unlock.busy)
                if let m = unlock.message {
                    Text(m).font(.system(size: 12)).multilineTextAlignment(.center).foregroundStyle(colors.accent)
                }
                HStack(spacing: 16) {
                    Button("Restore purchases") { Task { await unlock.restore(); if unlock.isUnlocked { withAnimation { done = true } } } }
                    Link("Terms", destination: Unlock.termsURL)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(colors.ink.opacity(0.55))
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            ZStack {
                Rectangle().fill(colors.accent).frame(width: 44, height: 44)
                Image(systemName: "checkmark").font(.system(size: 20, weight: .bold)).foregroundStyle(colors.background)
            }
            Text("Everything is open").font(.system(size: 22, weight: .semibold)).foregroundStyle(colors.ink)
            Text("Every level, every look, and your best scores kept.").font(.system(size: 14)).foregroundStyle(colors.ink.opacity(0.55))
            OutlineButton(title: "Play", colors: colors) { dismiss() }
                .padding(.top, 10)
        }
        .padding(.vertical, 10)
    }

    private var looks: some View {
        HStack(spacing: 2) {
            ForEach(Look.all.prefix(3)) { l in Rectangle().fill(l.accent.color).frame(width: 5, height: 12) }
        }
    }

    private var hue: some View {
        HStack(spacing: 2) {
            ForEach(Array(HueColor.logo(colors.accent).enumerated()), id: \.offset) { _, c in
                Rectangle().fill(c).frame(width: 5, height: 12)
            }
        }
    }

    private func perk(_ mark: some View, _ title: String, _ line: String) -> some View {
        HStack(spacing: 14) {
            mark.frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(colors.ink)
                Text(line).font(.system(size: 13)).foregroundStyle(colors.ink.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UnlockHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
