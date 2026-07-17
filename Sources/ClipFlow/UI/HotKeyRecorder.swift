import AppKit
import Carbon
import SwiftUI

struct HotKeyRecorder: NSViewRepresentable {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onChange = { code, flags in
            keyCode = code
            modifiers = flags
        }
        view.updateLabel(keyCode: keyCode, modifiers: modifiers)
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.updateLabel(keyCode: keyCode, modifiers: modifiers)
    }
}

final class RecorderView: NSView {
    var onChange: ((UInt32, UInt32) -> Void)?
    private let label = NSTextField(labelWithString: "")
    private var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        label.alignment = .center
        label.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        addSubview(label)
    }

    required init?(coder: NSCoder) { nil }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        label.frame = bounds.insetBy(dx: 7, dy: 4)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
        label.stringValue = "Type shortcut"
        layer?.borderColor = NSColor.controlAccentColor.cgColor
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        layer?.borderColor = NSColor.separatorColor.cgColor
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }
        let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard carbonModifiers != 0 else {
            NSSound.beep()
            return
        }
        onChange?(UInt32(event.keyCode), carbonModifiers)
        updateLabel(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers)
        window?.makeFirstResponder(nil)
    }

    func updateLabel(keyCode: UInt32, modifiers: UInt32) {
        guard !isRecording else { return }
        label.stringValue = Self.displayString(keyCode: keyCode, modifiers: modifiers)
    }

    private static func carbonModifiers(from modifiers: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if modifiers.contains(.command) { result |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { result |= UInt32(shiftKey) }
        if modifiers.contains(.option) { result |= UInt32(optionKey) }
        if modifiers.contains(.control) { result |= UInt32(controlKey) }
        return result
    }

    static func displayString(keyCode: UInt32, modifiers: UInt32) -> String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "\u{2303}" }
        if modifiers & UInt32(optionKey) != 0 { result += "\u{2325}" }
        if modifiers & UInt32(shiftKey) != 0 { result += "\u{21E7}" }
        if modifiers & UInt32(cmdKey) != 0 { result += "\u{2318}" }
        result += keyName(for: keyCode)
        return result
    }

    private static func keyName(for code: UInt32) -> String {
        let known: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P", 37: "L",
            38: "J", 40: "K", 45: "N", 46: "M", 49: "Space"
        ]
        return known[code] ?? "Key \(code)"
    }
}
