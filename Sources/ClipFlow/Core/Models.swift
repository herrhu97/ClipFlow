import Foundation

enum ClipboardContentType: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case richText
    case url
    case image
    case file
    case html

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: return "Text"
        case .richText: return "Rich Text"
        case .url: return "Link"
        case .image: return "Image"
        case .file: return "File"
        case .html: return "HTML"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .url: return "link"
        case .image: return "photo"
        case .file: return "doc"
        case .html: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct ClipboardItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let type: ClipboardContentType
    var textContent: String?
    var payloadPath: String?
    let contentHash: String
    var sourceAppIdentifier: String?
    var sourceAppName: String
    let createdAt: Date
    var lastCopiedAt: Date
    var lastUsedAt: Date?
    var isPinned: Bool
    var collectionID: UUID?
    var searchText: String
    var byteSize: Int64
    var favoriteOrder: Int
    /// Pre-normalized haystack (search text + source app name) maintained by `ClipStore`
    /// so quick-panel search does not re-fold every item on each keystroke.
    var searchIndex: String = ""

    private enum CodingKeys: String, CodingKey {
        case id, type, textContent, payloadPath, contentHash, sourceAppIdentifier, sourceAppName
        case createdAt, lastCopiedAt, lastUsedAt, isPinned, collectionID, searchText, byteSize, favoriteOrder
    }

    /// Rebuilds the normalized search haystack from the current search text and source app name.
    mutating func rebuildSearchIndex() {
        searchIndex = "\(searchText) \(sourceAppName)".normalizedForSearch
    }

    var title: String {
        let candidate = textContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !candidate.isEmpty {
            return candidate.components(separatedBy: .newlines).first ?? candidate
        }
        switch type {
        case .image:
            return "Image from \(sourceAppName)"
        case .file:
            return "File"
        default:
            return type.title
        }
    }

    var isFileAvailable: Bool {
        guard type == .file, let textContent else { return true }
        let paths = textContent.components(separatedBy: "\n").filter { !$0.isEmpty }
        return !paths.isEmpty && paths.allSatisfy { FileManager.default.fileExists(atPath: $0) }
    }
}

struct ClipCollection: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var sortOrder: Int
    let createdAt: Date
}

struct CapturedContent: Sendable {
    let type: ClipboardContentType
    let data: Data
    let displayText: String?
    let searchText: String
    let contentHash: String
    let sourceAppIdentifier: String?
    let sourceAppName: String
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case image
    case link
    case file
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All Clips"
        case .text: return "Text"
        case .image: return "Images"
        case .link: return "Links"
        case .file: return "Files"
        case .favorites: return "Favorites"
        }
    }

    var systemImage: String {
        switch self {
        case .all: return "clock.arrow.circlepath"
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .link: return "link"
        case .file: return "doc"
        case .favorites: return "pin"
        }
    }

    func includes(_ item: ClipboardItem) -> Bool {
        switch self {
        case .all: return true
        case .text: return [.text, .richText, .html].contains(item.type)
        case .image: return item.type == .image
        case .link: return item.type == .url
        case .file: return item.type == .file
        case .favorites: return item.isPinned
        }
    }
}

enum DuplicateHandling: String, CaseIterable, Identifiable {
    case moveToTop
    case ignore
    case keepBoth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .moveToTop: return "Move existing item to top"
        case .ignore: return "Ignore duplicate"
        case .keepBoth: return "Keep both copies"
        }
    }
}

enum RetentionPeriod: Int, CaseIterable, Identifiable {
    case day = 1
    case week = 7
    case month = 30
    case quarter = 90
    case year = 365
    case forever = 0

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .day: return "1 day"
        case .week: return "1 week"
        case .month: return "1 month"
        case .quarter: return "3 months"
        case .year: return "1 year"
        case .forever: return "Forever"
        }
    }
}

enum HistoryTimeRange: Int, CaseIterable, Identifiable {
    case anytime = 0
    case today = 1
    case week = 7
    case month = 30

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .anytime: return "Any time"
        case .today: return "Today"
        case .week: return "Past week"
        case .month: return "Past month"
        }
    }

    func includes(_ date: Date) -> Bool {
        guard self != .anytime,
              let cutoff = Calendar.current.date(byAdding: .day, value: -rawValue, to: Date()) else {
            return true
        }
        return date >= cutoff
    }
}

extension String {
    var normalizedForSearch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
