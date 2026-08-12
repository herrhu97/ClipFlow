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
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 366),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
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
        panel.minSize = NSSize(width: 760, height: 350)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .utilityWindow
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: QuickPanelView(store: store).environmentObject(state))

        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            let navigationModifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            switch event.keyCode {
            case 53:
                self.close()
                return nil
            case 124 where navigationModifiers.isEmpty:
                self.state.selectNext(offset: 1)
                return nil
            case 123 where navigationModifiers.isEmpty:
                self.state.selectNext(offset: -1)
                return nil
            case 125 where navigationModifiers.isEmpty:
                self.state.selectNext(offset: 1)
                return nil
            case 126 where navigationModifiers.isEmpty:
                self.state.selectNext(offset: -1)
                return nil
            case 36, 76:
                self.state.pasteSelected()
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
            let size = NSSize(
                width: min(max(760, visibleFrame.width - 48), 1380),
                height: min(366, visibleFrame.height - 24)
            )
            panel.setFrame(
                NSRect(
                    x: visibleFrame.midX - size.width / 2,
                    y: visibleFrame.minY + 12,
                    width: size.width,
                    height: size.height
                ),
                display: true
            )
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
