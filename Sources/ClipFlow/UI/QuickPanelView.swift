import AppKit
import ImageIO
import SwiftUI

struct QuickPanelView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var store: ClipStore
    @FocusState private var searchFocused: Bool
    @State private var isAddingCollection = false
    @State private var collectionName = ""
    @State private var renamingCollection: ClipCollection?

    private var visibleItems: [ClipboardItem] { state.filteredItems(in: store) }
    private var selectedItem: ClipboardItem? {
        guard let id = state.selectedItemID else { return visibleItems.first }
        return visibleItems.first(where: { $0.id == id }) ?? visibleItems.first
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 190)

            Divider()

            VStack(spacing: 0) {
                searchBar
                Divider()
                historyList
            }
            .frame(minWidth: 390)

            if state.isPreviewVisible {
                Divider()
                ItemPreviewView(item: selectedItem, store: store)
                    .frame(minWidth: 250, idealWidth: 290, maxWidth: 340)
            }
        }
        .frame(minWidth: 720, minHeight: 440)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            if let notice = state.notice {
                Text(notice)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
                    .padding(.bottom, 18)
            }
        }
        .onAppear {
            searchFocused = true
            if state.selectedItemID == nil { state.selectedItemID = visibleItems.first?.id }
        }
        .onChange(of: state.searchQuery) { _ in state.selectedItemID = visibleItems.first?.id }
        .onChange(of: state.selectedFilter) { _ in state.selectedItemID = visibleItems.first?.id }
        .onChange(of: state.selectedCollectionID) { _ in state.selectedItemID = visibleItems.first?.id }
        .sheet(item: $renamingCollection) { collection in
            RenameCollectionSheet(store: store, collection: collection)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ClipFlowMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ClipFlow").font(.headline)
                    Text(state.settings.isRecordingEnabled ? "Recording" : "Paused")
                        .font(.caption)
                        .foregroundStyle(state.settings.isRecordingEnabled ? Color.green : Color.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(HistoryFilter.allCases) { filter in
                        SidebarButton(
                            title: filter.title,
                            systemImage: filter.systemImage,
                            count: count(for: filter),
                            selected: state.selectedFilter == filter && state.selectedCollectionID == nil
                        ) {
                            state.selectedFilter = filter
                            state.selectedCollectionID = nil
                        }
                    }

                    HStack {
                        Text("GROUPS")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            isAddingCollection = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                        .help("New group")
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 18)
                    .padding(.bottom, 4)

                    ForEach(store.collections) { collection in
                        SidebarButton(
                            title: collection.name,
                            systemImage: "folder",
                            count: store.items.filter { $0.collectionID == collection.id }.count,
                            selected: state.selectedCollectionID == collection.id
                        ) {
                            state.selectedFilter = .all
                            state.selectedCollectionID = collection.id
                        }
                        .contextMenu {
                            Button("Rename") { renamingCollection = collection }
                            Button("Delete Group", role: .destructive) {
                                do { try store.deleteCollection(collection) }
                                catch { state.present(error) }
                                if state.selectedCollectionID == collection.id { state.selectedCollectionID = nil }
                            }
                        }
                    }

                    if isAddingCollection {
                        HStack(spacing: 5) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                            TextField("Group name", text: $collectionName)
                                .textFieldStyle(.plain)
                                .onSubmit { addCollection() }
                            Button { addCollection() } label: { Image(systemName: "checkmark") }
                                .buttonStyle(.plain)
                                .help("Create group")
                        }
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                    }
                }
                .padding(.horizontal, 7)
            }

            Divider()
            HStack {
                Button {
                    state.settings.isRecordingEnabled.toggle()
                } label: {
                    Label(
                        state.settings.isRecordingEnabled ? "Pause" : "Resume",
                        systemImage: state.settings.isRecordingEnabled ? "pause.fill" : "play.fill"
                    )
                }
                .buttonStyle(.plain)

                Spacer()

                Button { state.showSettings() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain)
                    .help("Settings")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(12)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search text, files, apps, and groups", text: $state.searchQuery)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($searchFocused)

            if !state.searchQuery.isEmpty {
                Button { state.searchQuery = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear search")
            }

            Picker("Time", selection: $state.selectedTimeRange) {
                ForEach(HistoryTimeRange.allCases) { range in Text(range.title).tag(range) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 100)

            Button { state.isPreviewVisible.toggle() } label: {
                Image(systemName: state.isPreviewVisible ? "sidebar.right" : "sidebar.right")
                    .symbolVariant(state.isPreviewVisible ? .fill : .none)
            }
            .buttonStyle(.plain)
            .help("Toggle preview")
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    @ViewBuilder
    private var historyList: some View {
        if visibleItems.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: state.searchQuery.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(.secondary)
                Text(state.searchQuery.isEmpty ? "No clips yet" : "No matching clips")
                    .font(.headline)
                Text(state.searchQuery.isEmpty ? "Copied content will appear here." : "Try another search or filter.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                            ClipboardItemRow(
                                item: item,
                                shortcutIndex: index < 9 ? index + 1 : nil,
                                isSelected: state.selectedItemID == item.id,
                                store: store
                            )
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture { state.selectedItemID = item.id }
                            .onTapGesture(count: 2) {
                                state.selectedItemID = item.id
                                state.paste(item, from: store)
                            }
                        }
                    }
                    .padding(7)
                }
                .onChange(of: state.selectedItemID) { id in
                    if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
        }
    }

    private func count(for filter: HistoryFilter) -> Int {
        store.items.filter(filter.includes).count
    }

    private func addCollection() {
        do {
            let collection = try store.createCollection(named: collectionName)
            state.selectedCollectionID = collection.id
            state.selectedFilter = .all
            collectionName = ""
            isAddingCollection = false
        } catch { state.present(error) }
    }
}

private struct SidebarButton: View {
    let title: String
    let systemImage: String
    let count: Int
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .frame(width: 16)
                    .foregroundStyle(selected ? Color.white : Color.secondary)
                Text(title).lineLimit(1)
                Spacer(minLength: 4)
                Text(count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 29)
            .background(selected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct ClipboardItemRow: View {
    @EnvironmentObject private var state: AppState
    let item: ClipboardItem
    let shortcutIndex: Int?
    let isSelected: Bool
    @ObservedObject var store: ClipStore

    var body: some View {
        HStack(spacing: 11) {
            ClipboardThumbnail(item: item, store: store)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(item.type == .text ? 2 : 1)
                    if !item.isFileAvailable {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .help("Original file is unavailable")
                    }
                }
                HStack(spacing: 6) {
                    SourceAppIcon(bundleIdentifier: item.sourceAppIdentifier)
                        .frame(width: 14, height: 14)
                    Text(item.sourceAppName).lineLimit(1)
                    Text("\u{00B7}")
                    Text(item.lastCopiedAt, style: .relative)
                    if let shortcutIndex {
                        Spacer()
                        Text("\u{2318}\(shortcutIndex)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 6)
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundStyle(Color.yellow)
                    .help("Pinned")
            }
            Image(systemName: item.type.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
                .help(item.type.title)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 61)
        .background(isSelected ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor).frame(width: 3).padding(.vertical, 7)
            }
        }
        .contextMenu {
            Button(item.isPinned ? "Unpin" : "Pin") {
                do { try store.setPinned(item, pinned: !item.isPinned) }
                catch { state.present(error) }
            }
            Menu("Move to Group") {
                Button("No Group") {
                    do { try store.move(item, to: nil) } catch { state.present(error) }
                }
                Divider()
                ForEach(store.collections) { collection in
                    Button(collection.name) {
                        do { try store.move(item, to: collection) } catch { state.present(error) }
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive) {
                do { try store.delete(item) } catch { state.present(error) }
            }
        }
    }
}

private struct ClipboardThumbnail: View {
    let item: ClipboardItem
    @ObservedObject var store: ClipStore
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(thumbnailColor)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: item.type.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(iconColor)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.08)))
        .task(id: item.id) {
            guard item.type == .image else { return }
            if let cached = ThumbnailCache.shared.image(for: item.id) {
                image = cached
                return
            }
            guard let data = try? store.payloadData(for: item),
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 160,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return }
            let decoded = NSImage(cgImage: thumbnail, size: .zero)
            ThumbnailCache.shared.insert(decoded, for: item.id)
            image = decoded
        }
    }

    private var thumbnailColor: Color {
        switch item.type {
        case .url: return Color.cyan.opacity(0.16)
        case .image: return Color.secondary.opacity(0.12)
        case .file: return Color.orange.opacity(0.16)
        case .html, .richText: return Color.green.opacity(0.14)
        case .text: return Color.accentColor.opacity(0.12)
        }
    }

    private var iconColor: Color {
        switch item.type {
        case .url: return .cyan
        case .file: return .orange
        case .html, .richText: return .green
        default: return .accentColor
        }
    }
}

@MainActor
private final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSUUID, NSImage>()

    private init() {
        cache.countLimit = 250
        cache.totalCostLimit = 32 * 1_024 * 1_024
    }

    func image(for id: UUID) -> NSImage? {
        cache.object(forKey: id as NSUUID)
    }

    func insert(_ image: NSImage, for id: UUID) {
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: id as NSUUID, cost: cost)
    }
}

private struct SourceAppIcon: View {
    let bundleIdentifier: String?

    var body: some View {
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
        } else {
            Image(systemName: "app.dashed")
                .resizable()
                .foregroundStyle(.secondary)
        }
    }
}

private struct ItemPreviewView: View {
    let item: ClipboardItem?
    @ObservedObject var store: ClipStore
    @State private var image: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Preview").font(.headline)
                Spacer()
                if let item { Image(systemName: item.type.systemImage).foregroundStyle(.secondary) }
            }
            .padding(14)
            Divider()

            if let item {
                Group {
                    if let image, item.type == .image {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(14)
                    } else if let text = item.textContent {
                        ScrollView {
                            Text(text)
                                .font(item.type == .text || item.type == .html ? .system(.body, design: .monospaced) : .body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: item.type.systemImage).font(.largeTitle)
                            Text(item.title).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    Label(item.sourceAppName, systemImage: "app")
                    Label(item.lastCopiedAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                    Label(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file), systemImage: "internaldrive")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(14)
            } else {
                Text("Select a clip to preview it.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .task(id: item?.id) {
            image = nil
            guard let item, item.type == .image,
                  let data = try? store.payloadData(for: item) else { return }
            image = NSImage(data: data)
        }
    }
}

private struct RenameCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ClipStore
    let collection: ClipCollection
    @State private var name: String

    init(store: ClipStore, collection: ClipCollection) {
        self.store = store
        self.collection = collection
        _name = State(initialValue: collection.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Group").font(.headline)
            TextField("Name", text: $name)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Rename") {
                    try? store.renameCollection(collection, to: name)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 330)
    }
}

struct ClipFlowMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(Color.accentColor)
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
