import AppKit
import SwiftUI

@MainActor
final class QuickPanelController: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let state: AppState
    private var keyboardMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    init(state: AppState, store: ClipStore) {
        self.state = state
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 550),
            styleMask: [.titled, .fullSizeContentView, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        super.init()
        panel.delegate = self
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.minSize = NSSize(width: 720, height: 440)
        panel.backgroundColor = .windowBackgroundColor
        panel.contentView = NSHostingView(rootView: QuickPanelView(store: store).environmentObject(state))

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            switch event.keyCode {
            case 53:
                self.close()
                return nil
            case 125:
                self.state.selectNext(offset: 1)
                return nil
            case 126:
                self.state.selectNext(offset: -1)
                return nil
            case 36, 76:
                self.state.pasteSelected()
                return nil
            case 49 where self.state.searchQuery.isEmpty:
                self.state.isPreviewVisible.toggle()
                return nil
            default:
                if event.modifierFlags.contains(.command),
                   let character = event.charactersIgnoringModifiers,
                   let number = Int(character),
                   (1...9).contains(number) {
                    self.state.selectAndPaste(position: number - 1)
                    return nil
                }
                return event
            }
        }
    }

    deinit {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
    }

    func show() {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
        if let visibleFrame = screen?.visibleFrame {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(
                x: visibleFrame.midX - size.width / 2,
                y: visibleFrame.midY - size.height / 2
            ))
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() { panel.orderOut(nil) }

    func windowWillClose(_ notification: Notification) { state.notice = nil }
}

@MainActor
final class SettingsWindowController {
    private let window: NSWindow

    init(state: AppState, store: ClipStore) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 670, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipFlow Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(store: store).environmentObject(state))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

@MainActor
final class OnboardingWindowController {
    private let window: NSWindow

    init(state: AppState, store: ClipStore) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 510),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(store: store).environmentObject(state))
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window.close() }
}
