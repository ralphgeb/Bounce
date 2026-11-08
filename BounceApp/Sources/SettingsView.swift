import SwiftUI
import UIKit

/// Light and dark, looks, the app icon, haptics, and your records in both games.
struct SettingsView: View {
    let colors: Colors
    @State private var settings = Settings.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("iconFollowsLook") private var iconFollowsLook = false
    @State private var tutorialsReset = false
    @State private var unlock = Unlock.shared
    @State private var showUnlock = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Appearance", selection: $settings.mode) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .listRowBackground(colors.ink.opacity(0.04))

                Section {
                    // The five looks as small 3 × 3 grids; the chosen one is outlined. One is free (picked
                    // at the start); the others open with Unlock everything.
                    HStack(spacing: 0) {
                        ForEach(Look.all) { look in
                            let chosen = look.id == settings.look.id
                            let open = settings.isLookOpen(look)
                            Button {
                                guard open else { showUnlock = true; return }
                                settings.lookID = look.id
                                Haptics.tap(.light)
                                if iconFollowsLook { setIcon(look) }
                            } label: {
                                VStack(spacing: 7) {
                                    LookSwatch(look: look, dark: scheme == .dark)
                                        .frame(width: 40, height: 40)
                                        .opacity(open ? 1 : 0.45)
                                        .overlay {
                                            if !open {
                                                Image(systemName: "lock.fill")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundStyle(colors.ink.opacity(0.75))
                                            }
                                        }
                                        .padding(5)
                                        .overlay(
                                            Rectangle()
                                                .strokeBorder(colors.ink, lineWidth: 1.5)
                                                .opacity(chosen ? 1 : 0)
                                        )
                                    Text(look.name)
                                        .font(.system(size: 10, weight: chosen ? .semibold : .regular))
                                        .foregroundStyle(colors.ink.opacity(chosen ? 0.9 : 0.5))
                                }
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(open ? look.name : "\(look.name), locked")
                            .accessibilityAddTraits(chosen ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                    Toggle("App icon follows the look", isOn: $iconFollowsLook)
                        .tint(colors.accent)
                        .onChange(of: iconFollowsLook) { _, on in setIcon(on ? settings.look : Look.all[0]) }
                } header: {
                    Text("Look · \(settings.look.name)")
                }
                .listRowBackground(colors.ink.opacity(0.04))

                Section {
                    Toggle("Haptics", isOn: $settings.haptics).tint(colors.accent)
                }
                .listRowBackground(colors.ink.opacity(0.04))

                Section {
                    Button {
                        Coach.resetAll()
                        tutorialsReset = true
                        Haptics.notify(.success)
                    } label: {
                        Text(tutorialsReset ? "Tutorials will show again" : "Show tutorials again")
                            .foregroundStyle(tutorialsReset ? colors.ink.opacity(0.5) : colors.accent)
                    }
                    .disabled(tutorialsReset)
                }
                .listRowBackground(colors.ink.opacity(0.04))

                Section {
                    if unlock.owned && !unlock.reset {
                        LabeledContent("Everything", value: "Unlocked")
                    } else {
                        Button { showUnlock = true } label: {
                            Text("Unlock everything · \(unlock.price)").foregroundStyle(colors.accent)
                        }
                    }
                    Button("Restore purchases") { Task { await unlock.restore() } }
                        .foregroundStyle(colors.ink)
                    Toggle("Apply paywall", isOn: $unlock.paywallOn).tint(colors.accent)
                    Button("Reset purchase") {
                        unlock.resetPurchase()
                        Haptics.notify(.warning)
                    }
                    .foregroundStyle(colors.ink)
                } header: {
                    Text("Unlock")
                } footer: {
                    Text("Apply paywall and Reset purchase are for trying it out: switch the paywall off to open everything, or reset to lock the games again and buy once more (in TestFlight nothing is charged).")
                }
                .listRowBackground(colors.ink.opacity(0.04))

                Section("Bounce") {
                    LabeledContent("Best score", value: "\(settings.best)")
                    LabeledContent("Longest game", value: settings.longest > 0 ? formatTime(settings.longest) : "–")
                }
                .listRowBackground(colors.ink.opacity(0.04))

                Section("Maze") {
                    LabeledContent("Deepest level", value: settings.mazeDeepest > 0 ? "\(settings.mazeDeepest)" : "–")
                    LabeledContent("Fastest level 1", value: settings.mazeTimes["1"].map(formatTime) ?? "–")
                }
                .listRowBackground(colors.ink.opacity(0.04))

                Section("Switch") {
                    LabeledContent("Best score", value: "\(settings.switchBest)")
                }
                .listRowBackground(colors.ink.opacity(0.04))

                Section("Hue") {
                    LabeledContent("Levels solved", value: "\(settings.hueSolved) of \(HueLevels.count)")
                }
                .listRowBackground(colors.ink.opacity(0.04))


                Section {
                    LabeledContent("Version", value: Bundle.main.version)
                }
                .listRowBackground(colors.ink.opacity(0.04))
            }
            .sheet(isPresented: $showUnlock) { UnlockSheet(colors: colors) }
            .scrollContentBackground(.hidden)
            .background(colors.background)
            .foregroundStyle(colors.ink)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(colors.ink)
                }
            }
        }
    }

    private func setIcon(_ look: Look) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons, app.alternateIconName != look.iconName else { return }
        app.setAlternateIconName(look.iconName) { _ in }
    }
}

/// A look as a small 3 × 3 grid: a blend from its light accent (top right) through the accent
/// (top left) to its main colour (bottom right), in OKLab so the steps look even.
struct LookSwatch: View {
    let look: Look
    let dark: Bool

    var body: some View {
        let p = dark ? look.dark : look.light
        let accent = HueColor.lab(look.accent)
        let ink = HueColor.lab(p.ink)
        let soft = HueColor.mix(accent, HueColor.lab(p.background), 0.6)
        let mid = HueColor.mix(accent, ink, 0.5)
        Canvas { ctx, size in
            let gap: CGFloat = 2
            let cell = (size.width - gap * 2) / 3
            for y in 0..<3 {
                for x in 0..<3 {
                    let u = Double(x) / 2, v = Double(y) / 2
                    // Corners: accent, soft accent, a mid tone, the main colour.
                    let top = HueColor.mix(accent, soft, u), bottom = HueColor.mix(mid, ink, u)
                    let c = HueColor.rgb(HueColor.mix(top, bottom, v)).color
                    ctx.fill(Path(CGRect(x: CGFloat(x) * (cell + gap), y: CGFloat(y) * (cell + gap), width: cell, height: cell)), with: .color(c))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

extension Bundle {
    var version: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
