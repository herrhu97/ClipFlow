import AppKit
import ImageIO
import SwiftUI

struct QuickPanelView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var store: ClipStore
    @FocusState private var searchFocused: Bool
    @State private var isAddingCollection = false
    @State private var renamingCollection: ClipCollection?

    private var visibleItems: [ClipboardItem] { state.filteredItems(in: store) }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            cardShelf
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 18, y: 7)
        .padding(12)
        .frame(minWidth: 760, minHeight: 350)
        .overlay(alignment: .bottom) {
            if let notice = state.notice {
                Text(notice)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.12)))
                    .padding(.bottom, 24)
            }
        }
        .onAppear {
            searchFocused = true
            selectFirstVisibleItem()
        }
        .onChange(of: state.searchQuery) { _ in selectFirstVisibleItem() }
        .onChange(of: state.selectedFilter) { _ in selectFirstVisibleItem() }
        .onChange(of: state.selectedCollectionID) { _ in selectFirstVisibleItem() }
        .onChange(of: state.selectedTimeRange) { _ in selectFirstVisibleItem() }
        .sheet(isPresented: $isAddingCollection) {
            NewCollectionSheet(store: store) { collection in
                state.selectedFilter = .all
                state.selectedCollectionID = collection.id
            }
        }
        .sheet(item: $renamingCollection) { collection in
            RenameCollectionSheet(store: store, collection: collection)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search clips", text: $state.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                if !state.searchQuery.isEmpty {
                    Button {
                        state.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 11)
            .frame(width: 210, height: 34)
            .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.08)))

            Divider()
                .frame(height: 24)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(HistoryFilter.allCases) { filter in
                        FilterTab(
                            filter: filter,
                            isSelected: state.selectedFilter == filter && state.selectedCollectionID == nil
                        ) {
                            state.selectedFilter = filter
                            state.selectedCollectionID = nil
                        }
                    }
                }
            }

            Spacer(minLength: 0)
            collectionMenu
            moreMenu
        }
        .padding(.horizontal, 20)
        .frame(height: 62)
    }

    private var collectionMenu: some View {
        Menu {
            Button {
                state.selectedCollectionID = nil
            } label: {
                if state.selectedCollectionID == nil {
                    Label("All Groups", systemImage: "checkmark")
                } else {
                    Text("All Groups")
                }
            }

            if !store.collections.isEmpty {
                Divider()
                ForEach(store.collections) { collection in
                    Button {
                        state.selectedFilter = .all
                        state.selectedCollectionID = collection.id
                    } label: {
                        if state.selectedCollectionID == collection.id {
                            Label(collection.name, systemImage: "checkmark")
                        } else {
                            Text(collection.name)
                        }
                    }
                }
            }

            Divider()
            Button {
                isAddingCollection = true
            } label: {
                Label("New Group", systemImage: "plus")
            }

            if let selectedCollection {
                Menu("Group Actions") {
                    Button("Rename Group") { renamingCollection = selectedCollection }
                    Button("Delete Group", role: .destructive) { delete(selectedCollection) }
                }
            }
        } label: {
            Label(selectedCollection?.name ?? "Groups", systemImage: "folder")
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Filter by group")
    }

    private var moreMenu: some View {
        Menu {
            Menu("Time Range") {
                ForEach(HistoryTimeRange.allCases) { range in
                    Button {
                        state.selectedTimeRange = range
                    } label: {
                        if state.selectedTimeRange == range {
                            Label(range.title, systemImage: "checkmark")
                        } else {
                            Text(range.title)
                        }
                    }
                }
            }

            Button {
                state.settings.isRecordingEnabled.toggle()
            } label: {
                Label(
                    state.settings.isRecordingEnabled ? "Pause Recording" : "Resume Recording",
                    systemImage: state.settings.isRecordingEnabled ? "pause.fill" : "play.fill"
                )
            }

            Divider()
            Button {
                state.showSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More options")
    }

    @ViewBuilder
    private var cardShelf: some View {
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
            .padding(.bottom, 18)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 14) {
                        ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                            ClipboardCard(
                                item: item,
                                shortcutIndex: index < 9 ? index + 1 : nil,
                                isSelected: state.selectedItemID == item.id,
                                store: store
                            )
                            .id(item.id)
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture {
                                state.selectedItemID = item.id
                            }
                            .onTapGesture(count: 2) {
                                state.selectedItemID = item.id
                                state.paste(item, from: store)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .onChange(of: state.selectedItemID) { id in
                    if let id {
                        withAnimation(.easeOut(duration: 0.16)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var selectedCollection: ClipCollection? {
        guard let id = state.selectedCollectionID else { return nil }
        return store.collections.first(where: { $0.id == id })
    }

    private func selectFirstVisibleItem() {
        state.selectedItemID = visibleItems.first?.id
    }

    private func delete(_ collection: ClipCollection) {
        do {
            try store.deleteCollection(collection)
            if state.selectedCollectionID == collection.id {
                state.selectedCollectionID = nil
            }
        } catch {
            state.present(error)
        }
    }
}

private struct FilterTab: View {
    let filter: HistoryFilter
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(filter.title, systemImage: filter.systemImage)
                .font(.callout.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(
                    isSelected ? Color.primary.opacity(0.11) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct ClipboardCard: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    let item: ClipboardItem
    let shortcutIndex: Int?
    let isSelected: Bool
    @ObservedObject var store: ClipStore
    @State private var imageAsset: ClipboardImageAsset?
    @State private var isHovered = false

    private var palette: ClipboardCardPalette { ClipboardCardPalette(item.type, colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 0) {
            cardHeader
            cardContent
            cardFooter
        }
        .frame(width: 252, height: 252)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                    lineWidth: isSelected ? 3 : 1
                )
        }
        .shadow(
            color: isSelected ? Color.accentColor.opacity(0.24) : Color.black.opacity(0.09),
            radius: isSelected ? 8 : 4,
            y: 2
        )
        .onHover { isHovered = $0 }
        .task(id: item.id) { loadImageAsset() }
        .contextMenu { contextMenu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.type.title) from \(item.sourceAppName): \(item.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var cardHeader: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Label(item.type.title, systemImage: item.type.systemImage)
                        .lineLimit(1)
                    if !item.isFileAvailable {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .help("Original file is unavailable")
                    }
                }
                .font(.headline)
                HStack(spacing: 7) {
                    Text(item.lastCopiedAt.clipCardRelativeLabel)
                    if let shortcutIndex {
                        Text("\u{2318}\(shortcutIndex)")
                            .font(.caption.monospaced())
                            .opacity(0.82)
                    }
                }
                .font(.caption)
            }
            .foregroundStyle(palette.headerForeground)

            Spacer(minLength: 0)
            SourceAppBadge(
                bundleIdentifier: item.sourceAppIdentifier,
                appName: item.sourceAppName
            )
        }
        .padding(.leading, 13)
        .padding(.trailing, 9)
        .padding(.vertical, 9)
        .frame(height: 60)
        .background(palette.header)
    }

    @ViewBuilder
    private var cardContent: some View {
        Group {
            if item.type == .image {
                imagePreview
            } else if item.type == .file {
                filePreview
            } else {
                textPreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(palette.surface)
    }

    private var imagePreview: some View {
        Group {
            if let imageAsset {
                Image(nsImage: imageAsset.image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                VStack(spacing: 7) {
                    Image(systemName: "photo")
                        .font(.system(size: 26, weight: .light))
                    Text("Loading preview")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var textPreview: some View {
        Text(item.textContent?.trimmingCharacters(in: .whitespacesAndNewlines) ?? item.title)
            .font(.system(size: 13.5, design: item.type == .html ? .monospaced : .default))
            .lineSpacing(3)
            .lineLimit(7)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(13)
            .textSelection(.enabled)
    }

    private var filePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(fileNames.prefix(4).enumerated()), id: \.offset) { _, name in
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(palette.header)
                    Text(name)
                        .lineLimit(2)
                }
                .font(.callout)
            }
            if fileNames.count > 4 {
                Text("+ \(fileNames.count - 4) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !item.isFileAvailable {
                Label("Original file unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(13)
    }

    private var cardFooter: some View {
        HStack(spacing: 6) {
            SourceAppIcon(bundleIdentifier: item.sourceAppIdentifier)
                .scaledToFit()
                .frame(width: 15, height: 15)
            Text(item.sourceAppName)
                .lineLimit(1)

            Spacer(minLength: 6)

            if isHovered {
                Button { togglePinned() } label: {
                    Image(systemName: item.isPinned ? "pin.slash" : "pin")
                }
                .buttonStyle(.plain)
                .help(item.isPinned ? "Unpin" : "Pin")

                Button { deleteItem() } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("Delete")
            } else {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .foregroundStyle(.orange)
                        .help("Pinned")
                }
                Text(metadata)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 11)
        .frame(height: 33)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.055 : 0.035))
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(item.isPinned ? "Unpin" : "Pin") { togglePinned() }
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
        Button("Delete", role: .destructive) { deleteItem() }
    }

    private var fileNames: [String] {
        (item.textContent ?? "")
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    private var metadata: String {
        if let imageAsset {
            return "\(imageAsset.pixelWidth) \u{00D7} \(imageAsset.pixelHeight)"
        }
        if item.type == .file {
            return "\(fileNames.count) \(fileNames.count == 1 ? "file" : "files")"
        }
        if let text = item.textContent {
            return "\(text.count.formatted()) chars"
        }
        return ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file)
    }

    private func loadImageAsset() {
        imageAsset = nil
        guard item.type == .image else { return }
        if let cached = ThumbnailCache.shared.asset(for: item.id) {
            imageAsset = cached
            return
        }
        guard let data = try? store.payloadData(for: item),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let pixelWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let pixelHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 520,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return }
        let asset = ClipboardImageAsset(
            image: NSImage(cgImage: thumbnail, size: .zero),
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
        ThumbnailCache.shared.insert(asset, for: item.id)
        imageAsset = asset
    }

    private func togglePinned() {
        do { try store.setPinned(item, pinned: !item.isPinned) }
        catch { state.present(error) }
    }

    private func deleteItem() {
        do { try store.delete(item) }
        catch { state.present(error) }
    }
}

private struct ClipboardCardPalette {
    let header: Color
    let surface: Color
    let headerForeground: Color

    init(_ type: ClipboardContentType, colorScheme: ColorScheme) {
        let isDark = colorScheme == .dark
        switch type {
        case .text:
            header = Color(red: 0.96, green: 0.67, blue: 0.16)
            surface = isDark ? Color(red: 0.22, green: 0.19, blue: 0.12) : Color(red: 1.0, green: 0.97, blue: 0.88)
            headerForeground = Color.black.opacity(0.82)
        case .richText:
            header = Color(red: 0.16, green: 0.62, blue: 0.39)
            surface = isDark ? Color(red: 0.11, green: 0.21, blue: 0.16) : Color(red: 0.91, green: 0.97, blue: 0.93)
            headerForeground = .white
        case .url:
            header = Color(red: 0.91, green: 0.28, blue: 0.33)
            surface = isDark ? Color(red: 0.24, green: 0.12, blue: 0.14) : Color(red: 1.0, green: 0.92, blue: 0.93)
            headerForeground = .white
        case .image:
            header = Color(red: 0.22, green: 0.48, blue: 0.90)
            surface = isDark ? Color(red: 0.11, green: 0.16, blue: 0.24) : Color(red: 0.91, green: 0.95, blue: 1.0)
            headerForeground = .white
        case .file:
            header = Color(red: 0.91, green: 0.47, blue: 0.14)
            surface = isDark ? Color(red: 0.24, green: 0.16, blue: 0.10) : Color(red: 1.0, green: 0.94, blue: 0.88)
            headerForeground = .white
        case .html:
            header = Color(red: 0.17, green: 0.19, blue: 0.22)
            surface = isDark ? Color(red: 0.14, green: 0.15, blue: 0.17) : Color(red: 0.94, green: 0.95, blue: 0.96)
            headerForeground = .white
        }
    }
}

private final class ClipboardImageAsset: NSObject {
    let image: NSImage
    let pixelWidth: Int
    let pixelHeight: Int

    init(image: NSImage, pixelWidth: Int, pixelHeight: Int) {
        self.image = image
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

@MainActor
private final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSUUID, ClipboardImageAsset>()

    private init() {
        cache.countLimit = 120
        cache.totalCostLimit = 48 * 1_024 * 1_024
    }

    func asset(for id: UUID) -> ClipboardImageAsset? {
        cache.object(forKey: id as NSUUID)
    }

    func insert(_ asset: ClipboardImageAsset, for id: UUID) {
        let cost = Int(asset.image.size.width * asset.image.size.height * 4)
        cache.setObject(asset, forKey: id as NSUUID, cost: cost)
    }
}

private struct SourceAppBadge: View {
    let bundleIdentifier: String?
    let appName: String

    var body: some View {
        SourceAppIcon(bundleIdentifier: bundleIdentifier)
            .scaledToFit()
            .frame(width: 31, height: 31)
            .padding(5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.35)))
            .help("Copied from \(appName)")
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

private struct NewCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    @ObservedObject var store: ClipStore
    let onCreate: (ClipCollection) -> Void
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Group").font(.headline)
            TextField("Name", text: $name)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 330)
    }

    private func create() {
        do {
            let collection = try store.createCollection(named: name)
            onCreate(collection)
            dismiss()
        } catch {
            state.present(error)
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

private extension Date {
    var clipCardRelativeLabel: String {
        let elapsed = max(0, Date().timeIntervalSince(self))
        if elapsed < 60 { return "Now" }
        if elapsed < 3_600 { return "\(Int(elapsed / 60))m ago" }
        if elapsed < 86_400 { return "\(Int(elapsed / 3_600))h ago" }
        if elapsed < 604_800 { return "\(Int(elapsed / 86_400))d ago" }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}
