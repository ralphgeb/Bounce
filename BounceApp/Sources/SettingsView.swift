import SwiftUI
import UIKit

/// Looks, light and dark, haptics, the app icon, and your records.
struct SettingsView: View {
    let colors: Colors
    @State private var settings = Settings.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("iconFollowsLook") private var iconFollowsLook = false

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
                    // The five looks as one line of accent squares; the chosen one is outlined.
                    HStack(spacing: 0) {
                        ForEach(Look.all) { look in
                            Button {
                                settings.lookID = look.id
                                Haptics.tap(.light)
                                if iconFollowsLook { setIcon(look) }
                            } label: {
                                Rectangle()
                                    .fill(look.accent.color)
                                    .frame(width: 30, height: 30)
                                    .padding(5)
                                    .overlay(
                                        Rectangle()
                                            .strokeBorder(colors.ink, lineWidth: 1.5)
                                            .opacity(look.id == settings.lookID ? 1 : 0)
                                    )
                                    .frame(maxWidth: .infinity)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(look.name)
                            .accessibilityAddTraits(look.id == settings.lookID ? .isSelected : [])
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

                Section("Records") {
                    LabeledContent("Best score", value: "\(settings.best)")
                    LabeledContent("Longest game", value: settings.longest > 0 ? formatTime(settings.longest) : "–")
                }
                .listRowBackground(colors.ink.opacity(0.04))

                Section {
                    LabeledContent("Version", value: Bundle.main.version)
                }
                .listRowBackground(colors.ink.opacity(0.04))
            }
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

extension Bundle {
    var version: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}
