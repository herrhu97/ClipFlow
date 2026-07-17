import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Key {
        static let recordingEnabled = "recordingEnabled"
        static let autoPasteEnabled = "autoPasteEnabled"
        static let retentionDays = "retentionDays"
        static let maximumStorageMB = "maximumStorageMB"
        static let duplicateHandling = "duplicateHandling"
        static let excludedApplications = "excludedApplications"
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let onboardingComplete = "onboardingComplete"
        static let launchAtLogin = "launchAtLogin"
    }

    static let defaultExcludedApplications: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.dashlane.Dashlane"
    ]

    private let defaults: UserDefaults

    @Published var isRecordingEnabled: Bool { didSet { defaults.set(isRecordingEnabled, forKey: Key.recordingEnabled) } }
    @Published var isAutoPasteEnabled: Bool { didSet { defaults.set(isAutoPasteEnabled, forKey: Key.autoPasteEnabled) } }
    @Published var retentionPeriod: RetentionPeriod { didSet { defaults.set(retentionPeriod.rawValue, forKey: Key.retentionDays) } }
    @Published var maximumStorageMB: Int { didSet { defaults.set(maximumStorageMB, forKey: Key.maximumStorageMB) } }
    @Published var duplicateHandling: DuplicateHandling { didSet { defaults.set(duplicateHandling.rawValue, forKey: Key.duplicateHandling) } }
    @Published var excludedApplications: Set<String> { didSet { defaults.set(Array(excludedApplications).sorted(), forKey: Key.excludedApplications) } }
    @Published var hotKeyCode: UInt32 { didSet { defaults.set(Int(hotKeyCode), forKey: Key.hotKeyCode) } }
    @Published var hotKeyModifiers: UInt32 { didSet { defaults.set(Int(hotKeyModifiers), forKey: Key.hotKeyModifiers) } }
    @Published var onboardingComplete: Bool { didSet { defaults.set(onboardingComplete, forKey: Key.onboardingComplete) } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.recordingEnabled: true,
            Key.autoPasteEnabled: true,
            Key.retentionDays: RetentionPeriod.month.rawValue,
            Key.maximumStorageMB: 512,
            Key.duplicateHandling: DuplicateHandling.moveToTop.rawValue,
            Key.excludedApplications: Array(Self.defaultExcludedApplications),
            Key.hotKeyCode: 9,
            Key.hotKeyModifiers: 768,
            Key.onboardingComplete: false,
            Key.launchAtLogin: false
        ])

        isRecordingEnabled = defaults.bool(forKey: Key.recordingEnabled)
        isAutoPasteEnabled = defaults.bool(forKey: Key.autoPasteEnabled)
        retentionPeriod = RetentionPeriod(rawValue: defaults.integer(forKey: Key.retentionDays)) ?? .month
        maximumStorageMB = max(64, defaults.integer(forKey: Key.maximumStorageMB))
        duplicateHandling = DuplicateHandling(rawValue: defaults.string(forKey: Key.duplicateHandling) ?? "") ?? .moveToTop
        excludedApplications = Set(defaults.stringArray(forKey: Key.excludedApplications) ?? Array(Self.defaultExcludedApplications))
        hotKeyCode = UInt32(defaults.integer(forKey: Key.hotKeyCode))
        hotKeyModifiers = UInt32(defaults.integer(forKey: Key.hotKeyModifiers))
        onboardingComplete = defaults.bool(forKey: Key.onboardingComplete)
        launchAtLogin = defaults.bool(forKey: Key.launchAtLogin)
    }
}
