import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var settings: AppSettings

    var body: some View {
        Group {
            Button {
                state.showQuickPanel()
            } label: {
                Label("Open ClipFlow", systemImage: "rectangle.on.rectangle")
            }
            .keyboardShortcut("v", modifiers: [.command, .shift])

            Button {
                settings.isRecordingEnabled.toggle()
            } label: {
                Label(
                    settings.isRecordingEnabled ? "Pause Recording" : "Resume Recording",
                    systemImage: settings.isRecordingEnabled ? "pause.fill" : "play.fill"
                )
            }

            Divider()

            if let store = state.store {
                Text("\(store.items.count.formatted()) saved clips")
            } else {
                Text("History unavailable")
            }

            Divider()

            Button { state.showSettings() } label: { Label("Settings...", systemImage: "gearshape") }
            Button { NSApp.terminate(nil) } label: { Label("Quit ClipFlow", systemImage: "power") }
                .keyboardShortcut("q")
        }
    }
}
