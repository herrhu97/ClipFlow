import SwiftUI

@main
struct ClipFlowApp: App {
    @StateObject private var state: AppState

    init() {
        let appState = AppState()
        _state = StateObject(wrappedValue: appState)
        DispatchQueue.main.async { appState.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(settings: state.settings)
                .environmentObject(state)
        } label: {
            MenuBarStatusLabel(settings: state.settings)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarStatusLabel: View {
    @ObservedObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: settings.isRecordingEnabled ? "doc.on.clipboard.fill" : "pause.circle.fill")
            Text("ClipFlow")
        }
        .accessibilityLabel(settings.isRecordingEnabled ? "ClipFlow, recording" : "ClipFlow, paused")
    }
}
