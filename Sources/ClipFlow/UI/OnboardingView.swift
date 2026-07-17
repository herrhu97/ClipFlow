import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var store: ClipStore
    @State private var page = 0

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcomePage
                case 1: privacyPage
                case 2: shortcutPage
                default: retentionPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 64)
            .padding(.top, 48)

            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.25))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if page > 0 { Button("Back") { page -= 1 } }
                Button(page == 3 ? "Start ClipFlow" : "Continue") {
                    if page == 3 {
                        state.addExampleClipIfNeeded()
                        state.finishOnboarding()
                    } else {
                        page += 1
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .frame(height: 64)
        }
        .frame(width: 700, height: 510)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var welcomePage: some View {
        VStack(spacing: 20) {
            ClipFlowMark(size: 82)
            Text("ClipFlow")
                .font(.system(size: 34, weight: .bold))
            Text("Your recent text, links, images, and files stay close at hand.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 470)
            HStack(spacing: 32) {
                FeatureLabel(icon: "clock.arrow.circlepath", title: "Find past clips")
                FeatureLabel(icon: "magnifyingglass", title: "Search instantly")
                FeatureLabel(icon: "keyboard", title: "Work by keyboard")
            }
            .padding(.top, 14)
        }
    }

    private var privacyPage: some View {
        VStack(alignment: .leading, spacing: 22) {
            PageHeading(icon: "hand.raised.fill", title: "Private by default", subtitle: "Clipboard history stays on this Mac.")
            VStack(alignment: .leading, spacing: 16) {
                PrivacyLine(icon: "lock.fill", title: "Encrypted storage", detail: "Clipboard content is encrypted with a key in your macOS Keychain.")
                PrivacyLine(icon: "eye.slash.fill", title: "Sensitive content protection", detail: "Private pasteboard types and common credential patterns are ignored.")
                PrivacyLine(icon: "nosign", title: "Application exclusions", detail: "Password managers are excluded by default. Add more apps in Settings.")
                PrivacyLine(icon: "icloud.slash", title: "No cloud upload", detail: "This version does not sync or analyze clipboard content online.")
            }
        }
    }

    private var shortcutPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(icon: "keyboard.fill", title: "Open from anywhere", subtitle: "Choose the shortcut that brings up your clipboard history.")
            HStack {
                Text("Global shortcut").font(.headline)
                Spacer()
                HotKeyRecorder(
                    keyCode: Binding(
                        get: { state.settings.hotKeyCode },
                        set: { state.settings.hotKeyCode = $0 }
                    ),
                    modifiers: Binding(
                        get: { state.settings.hotKeyModifiers },
                        set: { state.settings.hotKeyModifiers = $0 }
                    )
                )
                    .frame(width: 150, height: 34)
            }
            .padding(.vertical, 18)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Label("Arrow keys move through history", systemImage: "arrow.up.arrow.down")
                Label("Return selects and pastes", systemImage: "return")
                Label("Command-number picks one of the first nine clips", systemImage: "number")
                Label("Escape closes the panel", systemImage: "escape")
            }
            .foregroundStyle(.secondary)
        }
    }

    private var retentionPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(icon: "internaldrive.fill", title: "Set your history limit", subtitle: "Old unpinned clips are cleaned up automatically.")
            Picker("Keep history", selection: Binding(
                get: { state.settings.retentionPeriod },
                set: { state.settings.retentionPeriod = $0 }
            )) {
                ForEach(RetentionPeriod.allCases) { period in Text(period.title).tag(period) }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 8) {
                Text("Automatic paste is optional").font(.headline)
                Text("ClipFlow can paste into the app you were using after you grant Accessibility access. Without it, your selection is copied back to the clipboard and you can press Command-V yourself.")
                    .foregroundStyle(.secondary)
                if !state.hasAccessibilityPermission {
                    Button("Request Accessibility Access") { state.requestAccessibilityPermission() }
                }
            }
            .padding(.top, 8)
            Text("A sample clip will be added so you can try search immediately.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct FeatureLabel: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.title2).foregroundStyle(Color.accentColor)
            Text(title).font(.callout)
        }
        .frame(width: 130)
    }
}

private struct PageHeading: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
        }
    }
}

private struct PrivacyLine: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: icon).foregroundStyle(Color.accentColor).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
