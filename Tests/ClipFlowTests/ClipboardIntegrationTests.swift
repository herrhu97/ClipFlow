import AppKit
import Foundation
import Testing
@testable import ClipFlow

@Suite("Clipboard integration", .serialized)
@MainActor
struct ClipboardIntegrationTests {
    @Test("Monitor captures a plain-text pasteboard change")
    func monitorCapturesPlainTextChange() throws {
        let suiteName = "ClipFlowTests.Settings.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AppSettings(defaults: defaults)
        let pasteboard = NSPasteboard(name: .init("ClipFlowTests.\(UUID().uuidString)"))
        pasteboard.clearContents()
        let monitor = ClipboardMonitor(pasteboard: pasteboard, settings: settings)
        var captured: CapturedContent?
        monitor.start { captured = $0 }

        pasteboard.clearContents()
        pasteboard.setString("integration clipboard text", forType: .string)
        monitor.poll()
        monitor.stop()

        #expect(captured?.type == .text)
        #expect(captured?.displayText == "integration clipboard text")
        #expect(captured?.searchText.contains("integration clipboard text") == true)
    }

    @Test("Paste service restores text without Accessibility permission")
    func pasteServiceRestoresTextForManualPaste() throws {
        let pasteboard = NSPasteboard(name: .init("ClipFlowTests.\(UUID().uuidString)"))
        let service = PasteService(pasteboard: pasteboard)
        let item = ClipboardItem(
            id: UUID(),
            type: .text,
            textContent: "restored text",
            payloadPath: nil,
            contentHash: "hash",
            sourceAppIdentifier: nil,
            sourceAppName: "Tests",
            createdAt: Date(),
            lastCopiedAt: Date(),
            lastUsedAt: nil,
            isPinned: false,
            collectionID: nil,
            searchText: "restored text",
            byteSize: 13,
            favoriteOrder: 0
        )

        let result = try service.restore(
            item,
            payload: Data("restored text".utf8),
            targetApplication: nil,
            autoPaste: true
        )
        if case .pasted = result {
            Issue.record("Expected clipboard-only fallback without a target application.")
        }
        #expect(pasteboard.string(forType: .string) == "restored text")
    }
}
