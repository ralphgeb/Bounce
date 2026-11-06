import SwiftUI
import UIKit

/// Looks, light and dark, haptics, the app icon, and your records.
struct SettingsView: View {
    let colors: Colors
    @State private var settings = Settings.shared
    @Environment(\.dismiss) private var dismiss
    @AppStorage("iconFollowsLook") private var iconFollowsLook = true

    var body: some View {
        NavigationStack {
            List {
                Section("Look") {
                    ForEach(Look.all) { look in
                        Button {
                            settings.lookID = look.id
                            Haptics.tap(.light)
                            if iconFollowsLook { setIcon(look) }
                        } label: {
                            HStack(spacing: 14) {
                                Image(look.previewImage)
                                    .resizable()
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                Text(look.name).foregroundStyle(colors.ink)
                                Spacer()
                                if look.id == settings.lookID {
                                    Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(colors.accent)
                                }
                            }
                        }
                    }
                    Toggle("App icon follows the look", isOn: $iconFollowsLook)
                        .tint(colors.accent)
                        .onChange(of: iconFollowsLook) { _, on in if on { setIcon(settings.look) } }
                }
                .listRowBackground(colors.ink.opacity(0.04))

                Section("Appearance") {
                    Picker("Appearance", selection: $settings.mode) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
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
