import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var store: ClipStore

    var body: some View {
        TabView {
            GeneralSettingsView(settings: state.settings)
                .environmentObject(state)
                .tabItem { Label("General", systemImage: "gearshape") }
            HistorySettingsView(settings: state.settings, store: store)
                .environmentObject(state)
                .tabItem { Label("History", systemImage: "clock") }
            PrivacySettingsView(settings: state.settings)
                .environmentObject(state)
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            DataSettingsView(store: store)
                .environmentObject(state)
                .tabItem { Label("Data", systemImage: "internaldrive") }
        }
        .padding(20)
        .frame(width: 670, height: 500)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var settings: AppSettings

    var body: some View {
        Form {
            Section("Clipboard") {
                Toggle("Record new clipboard content", isOn: $settings.isRecordingEnabled)
                Toggle("Paste automatically after selection", isOn: $settings.isAutoPasteEnabled)
                Picker("Duplicate content", selection: $settings.duplicateHandling) {
                    ForEach(DuplicateHandling.allCases) { option in Text(option.title).tag(option) }
                }
            }

            Section("Quick Panel") {
                LabeledContent("Global shortcut") {
                    HotKeyRecorder(keyCode: $settings.hotKeyCode, modifiers: $settings.hotKeyModifiers)
                        .frame(width: 130, height: 30)
                }
                Text("Click the shortcut field, then press a modified key combination.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System") {
                Toggle("Open ClipFlow at login", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { state.updateLaunchAtLogin($0) }
                ))
                Button("Show Welcome Guide") { state.showOnboarding() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct HistorySettingsView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ClipStore

    var body: some View {
        Form {
            Section("Retention") {
                Picker("Keep history", selection: $settings.retentionPeriod) {
                    ForEach(RetentionPeriod.allCases) { period in Text(period.title).tag(period) }
                }
                Stepper(value: $settings.maximumStorageMB, in: 64...8_192, step: 64) {
                    LabeledContent("Maximum storage") {
                        Text(ByteCountFormatter.string(
                            fromByteCount: Int64(settings.maximumStorageMB) * 1_024 * 1_024,
                            countStyle: .file
                        ))
                    }
                }
                Text("Pinned clips are not removed by automatic cleanup.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Current Usage") {
                LabeledContent("Saved clips", value: store.items.count.formatted())
                LabeledContent("Payload size", value: ByteCountFormatter.string(
                    fromByteCount: store.items.reduce(Int64(0)) { $0 + $1.byteSize },
                    countStyle: .file
                ))
            }

            Section {
                Button("Clear All History", role: .destructive) { state.clearHistory() }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettingsView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var settings: AppSettings
    @State private var bundleIdentifier = ""

    var body: some View {
        Form {
            Section("Automatic Paste") {
                HStack {
                    Label(
                        state.hasAccessibilityPermission ? "Accessibility permission granted" : "Accessibility permission not granted",
                        systemImage: state.hasAccessibilityPermission ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    .foregroundStyle(state.hasAccessibilityPermission ? Color.green : Color.secondary)
                    Spacer()
                    if !state.hasAccessibilityPermission {
                        Button("Request Access") { state.requestAccessibilityPermission() }
                    }
                }
                Text("Without this permission, ClipFlow still restores the selected item to the clipboard for manual paste.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Excluded Applications") {
                if settings.excludedApplications.isEmpty {
                    Text("No applications are excluded.").foregroundStyle(.secondary)
                } else {
                    ForEach(settings.excludedApplications.sorted(), id: \.self) { identifier in
                        HStack {
                            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable().frame(width: 22, height: 22)
                            } else {
                                Image(systemName: "app.dashed").frame(width: 22)
                            }
                            Text(identifier).lineLimit(1)
                            Spacer()
                            Button {
                                settings.excludedApplications.remove(identifier)
                            } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain)
                            .help("Remove exclusion")
                        }
                    }
                }

                HStack {
                    TextField("Application bundle identifier", text: $bundleIdentifier)
                    Button("Add") { addBundleIdentifier() }
                        .disabled(bundleIdentifier.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Choose App") { chooseApplication() }
                }
            }

            Section("Built-in Protection") {
                Text("ClipFlow ignores pasteboard content marked transient or concealed, common one-time-code and credential patterns, valid payment-card numbers, and private keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func addBundleIdentifier() {
        let value = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        settings.excludedApplications.insert(value)
        bundleIdentifier = ""
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK,
              let url = panel.url,
              let identifier = Bundle(url: url)?.bundleIdentifier else { return }
        settings.excludedApplications.insert(identifier)
    }
}

private struct DataSettingsView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var store: ClipStore

    var body: some View {
        Form {
            Section("Local Data") {
                LabeledContent("Storage", value: "On this Mac")
                LabeledContent("Encryption", value: "AES-256-GCM")
                LabeledContent("Cloud sync", value: "Off")
                Text("Clip content is not uploaded for analytics. Encryption keys are stored in the macOS Keychain and cannot leave this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Export and Delete") {
                Button("Export History...") { state.exportHistory() }
                Button("Delete All Local Data", role: .destructive) { state.clearHistory() }
            }
        }
        .formStyle(.grouped)
    }
}
