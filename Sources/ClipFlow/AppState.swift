import AppKit
import Combine
import CryptoKit
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    @Published var selectedFilter: HistoryFilter = .all
    @Published var selectedCollectionID: UUID?
    @Published var selectedTimeRange: HistoryTimeRange = .anytime
    @Published var searchQuery = ""
    @Published var selectedItemID: UUID?
    @Published var isPreviewVisible = false
    @Published var notice: String?
    @Published var startupError: String?
    @Published private(set) var store: ClipStore?

    let settings: AppSettings
    private let pasteService = PasteService()
    private let globalHotKey = GlobalHotKey()
    private var clipboardMonitor: ClipboardMonitor?
    private var quickPanelController: QuickPanelController?
    private var settingsWindowController: SettingsWindowController?
    private var onboardingWindowController: OnboardingWindowController?
    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false
    private(set) var targetApplication: NSRunningApplication?

    init(settings: AppSettings) {
        self.settings = settings
    }

    convenience init() {
        self.init(settings: AppSettings())
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        NSApp.setActivationPolicy(.accessory)

        do {
            let store = try ClipStore()
            self.store = store
            try store.performCleanup(
                retention: settings.retentionPeriod,
                maximumStorageMB: settings.maximumStorageMB
            )
            let monitor = ClipboardMonitor(settings: settings)
            monitor.start { [weak self, weak store] capture in
                guard let self, let store else { return }
                do {
                    _ = try store.add(capture, duplicateHandling: self.settings.duplicateHandling)
                } catch {
                    self.present(error)
                }
            }
            clipboardMonitor = monitor
        } catch {
            startupError = error.localizedDescription
        }

        registerHotKey()
        settings.$hotKeyCode
            .combineLatest(settings.$hotKeyModifiers)
            .dropFirst()
            .sink { [weak self] _, _ in self?.registerHotKey() }
            .store(in: &cancellables)

        settings.$retentionPeriod
            .combineLatest(settings.$maximumStorageMB)
            .dropFirst()
            .sink { [weak self] retention, maximum in
                guard let self, let store = self.store else { return }
                do { try store.performCleanup(retention: retention, maximumStorageMB: maximum) }
                catch { self.present(error) }
            }
            .store(in: &cancellables)

        if !settings.onboardingComplete, let store {
            onboardingWindowController = OnboardingWindowController(state: self, store: store)
            onboardingWindowController?.show()
        }
    }

    func filteredItems(in store: ClipStore) -> [ClipboardItem] {
        let queryTerms = searchQuery.normalizedForSearch.split(whereSeparator: \.isWhitespace).map(String.init)
        let collectionName = selectedCollectionID.flatMap { id in store.collections.first(where: { $0.id == id })?.name }
        let result = store.items.filter { item in
            guard selectedFilter.includes(item),
                  selectedTimeRange.includes(item.lastCopiedAt),
                  selectedCollectionID == nil || item.collectionID == selectedCollectionID else { return false }
            guard !queryTerms.isEmpty else { return true }
            let groupName = item.collectionID.flatMap { id in store.collections.first(where: { $0.id == id })?.name } ?? collectionName ?? ""
            let haystack = "\(item.searchText) \(item.sourceAppName) \(groupName)".normalizedForSearch
            return queryTerms.allSatisfy { haystack.contains($0) }
        }
        if selectedFilter == .favorites {
            return result.sorted {
                if $0.favoriteOrder == $1.favoriteOrder { return $0.lastCopiedAt > $1.lastCopiedAt }
                return $0.favoriteOrder < $1.favoriteOrder
            }
        }
        return result
    }

    func showQuickPanel() {
        guard let store else {
            if let startupError { showAlert(title: "ClipFlow could not start", message: startupError) }
            return
        }
        if quickPanelController == nil { quickPanelController = QuickPanelController(state: self, store: store) }
        if quickPanelController?.isVisible == true {
            quickPanelController?.close()
            return
        }
        let current = NSWorkspace.shared.frontmostApplication
        if current?.bundleIdentifier != Bundle.main.bundleIdentifier { targetApplication = current }
        searchQuery = ""
        selectedTimeRange = .anytime
        let filtered = filteredItems(in: store)
        selectedItemID = filtered.first?.id
        quickPanelController?.show()
    }

    func closeQuickPanel() {
        quickPanelController?.close()
    }

    func selectNext(offset: Int) {
        guard let store else { return }
        let visible = filteredItems(in: store)
        guard !visible.isEmpty else { selectedItemID = nil; return }
        let currentIndex = selectedItemID.flatMap { id in visible.firstIndex(where: { $0.id == id }) } ?? 0
        selectedItemID = visible[min(max(currentIndex + offset, 0), visible.count - 1)].id
    }

    func selectAndPaste(position: Int) {
        guard let store else { return }
        let visible = filteredItems(in: store)
        guard visible.indices.contains(position) else { return }
        selectedItemID = visible[position].id
        pasteSelected()
    }

    func pasteSelected() {
        guard let store else { return }
        let visible = filteredItems(in: store)
        guard let item = selectedItemID.flatMap({ id in visible.first(where: { $0.id == id }) }) ?? visible.first else { return }
        paste(item, from: store)
    }

    func paste(_ item: ClipboardItem, from store: ClipStore) {
        do {
            let payload = try store.payloadData(for: item)
            let result = try pasteService.restore(
                item,
                payload: payload,
                targetApplication: targetApplication,
                autoPaste: settings.isAutoPasteEnabled
            )
            clipboardMonitor?.suppressCurrentChange()
            try store.markUsed(item)
            switch result {
            case .pasted:
                closeQuickPanel()
            case .copiedForManualPaste:
                notice = "Copied to the clipboard. Press Command-V to paste."
                targetApplication?.activate(options: [.activateIgnoringOtherApps])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                    self?.closeQuickPanel()
                    self?.notice = nil
                }
            }
        } catch {
            present(error)
        }
    }

    func showSettings() {
        guard let store else { return }
        closeQuickPanel()
        if settingsWindowController == nil { settingsWindowController = SettingsWindowController(state: self, store: store) }
        settingsWindowController?.show()
    }

    func showOnboarding() {
        guard let store else { return }
        if onboardingWindowController == nil { onboardingWindowController = OnboardingWindowController(state: self, store: store) }
        onboardingWindowController?.show()
    }

    func finishOnboarding() {
        settings.onboardingComplete = true
        onboardingWindowController?.close()
        onboardingWindowController = nil
        DispatchQueue.main.async { [weak self] in self?.showQuickPanel() }
    }

    func requestAccessibilityPermission() {
        pasteService.requestAccessibilityPermission()
    }

    var hasAccessibilityPermission: Bool { pasteService.hasAccessibilityPermission }

    func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            settings.launchAtLogin = enabled
        } catch {
            settings.launchAtLogin = false
            present(error)
        }
    }

    func exportHistory() {
        guard let store else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ClipFlow Export.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData(to: url)
            notice = "History exported."
        } catch { present(error) }
    }

    func clearHistory() {
        guard let store else { return }
        let alert = NSAlert()
        alert.messageText = "Clear all clipboard history?"
        alert.informativeText = "This permanently deletes every saved clip, cached payload, and image. This cannot be undone."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do { try store.clearHistory() }
        catch { present(error) }
    }

    func addExampleClipIfNeeded() {
        guard let store, store.items.isEmpty else { return }
        let text = "ClipFlow keeps useful clipboard history on this Mac."
        let data = Data(text.utf8)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let capture = CapturedContent(
            type: .text,
            data: data,
            displayText: text,
            searchText: "\(text) ClipFlow",
            contentHash: digest,
            sourceAppIdentifier: Bundle.main.bundleIdentifier,
            sourceAppName: "ClipFlow"
        )
        do { _ = try store.add(capture, duplicateHandling: .ignore) }
        catch { present(error) }
    }

    func present(_ error: Error) {
        showAlert(title: "ClipFlow", message: error.localizedDescription)
    }

    private func registerHotKey() {
        let registered = globalHotKey.register(
            keyCode: settings.hotKeyCode,
            modifiers: settings.hotKeyModifiers
        ) { [weak self] in self?.showQuickPanel() }
        if !registered { startupError = "The selected global shortcut is already in use." }
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
