import AppKit
import ApplicationServices
import Foundation

enum PasteResult {
    case pasted
    case copiedForManualPaste
}

@MainActor
final class PasteService {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func restore(
        _ item: ClipboardItem,
        payload: Data,
        targetApplication: NSRunningApplication?,
        autoPaste: Bool
    ) throws -> PasteResult {
        pasteboard.clearContents()
        switch item.type {
        case .text:
            guard let string = String(data: payload, encoding: .utf8) else { throw ClipStoreError.encoding }
            pasteboard.setString(string, forType: .string)
        case .url:
            guard let string = String(data: payload, encoding: .utf8) else { throw ClipStoreError.encoding }
            pasteboard.setString(string, forType: .string)
            pasteboard.setString(string, forType: .URL)
        case .richText:
            pasteboard.setData(payload, forType: .rtf)
            if let attributed = NSAttributedString(rtf: payload, documentAttributes: nil) {
                pasteboard.setString(attributed.string, forType: .string)
            }
        case .html:
            pasteboard.setData(payload, forType: .html)
            if let attributed = NSAttributedString(
                html: payload,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
            ) {
                pasteboard.setString(attributed.string, forType: .string)
            }
        case .image:
            guard let image = NSImage(data: payload) else { throw ClipStoreError.encoding }
            pasteboard.writeObjects([image])
        case .file:
            let paths = try JSONDecoder().decode([String].self, from: payload)
            pasteboard.writeObjects(paths.map { NSURL(fileURLWithPath: $0) })
        }

        guard autoPaste, hasAccessibilityPermission, let targetApplication else {
            return .copiedForManualPaste
        }
        targetApplication.activate(options: [.activateIgnoringOtherApps])
        postCommandVWhenActive(targetApplication)
        return .pasted
    }

    /// Waits until the target application is actually frontmost before posting Command-V,
    /// instead of relying on a fixed delay that loses the keystroke when activation is
    /// slow. Falls back to posting after a timeout so the paste is never silently dropped.
    private func postCommandVWhenActive(_ application: NSRunningApplication) {
        Task { [weak self] in
            let deadline = Date().addingTimeInterval(1.0)
            while !application.isActive && Date() < deadline {
                try? await Task.sleep(nanoseconds: 25_000_000)
            }
            // Brief settle time so the target's key window is ready to receive the event.
            try? await Task.sleep(nanoseconds: 30_000_000)
            self?.postCommandV()
        }
    }

    private func postCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
