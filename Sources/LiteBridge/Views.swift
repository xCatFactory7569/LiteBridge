import SwiftUI
import AppKit

// MARK: - Helpers

/// Lays chips out left to right and wraps to the next line, with even spacing.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

func finderTagColor(_ index: Int?) -> Color? {
    switch index {
    case 1: return .gray
    case 2: return .green
    case 3: return .purple
    case 4: return .blue
    case 5: return .yellow
    case 6: return .red
    case 7: return .orange
    default: return nil
    }
}

// MARK: - Main layout

struct ContentView: View {
    @EnvironmentObject var lib: Library
    @State private var dropping = false

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 170, ideal: 220, max: 340)
        } detail: {
            if lib.folder == nil {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 48)).foregroundColor(.secondary)
                    Text("Open a folder to start").font(.title3)
                    Text("or drag a folder onto this window").font(.callout).foregroundColor(.secondary)
                    Button("Open Folder…") { lib.chooseFolder() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    GridPane().frame(minWidth: 360)
                    if lib.showPreview {
                        PreviewPane().frame(minWidth: 320, idealWidth: 560)
                    }
                }
            }
        }
        .navigationTitle(lib.inBin ? "Review Bin" : (lib.folder?.lastPathComponent ?? "LiteBridge"))
        .searchable(text: $lib.search, prompt: "Filter by name or tag")
        .dropDestination(for: URL.self, action: { urls, _ in
            let dir = urls.first { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            guard let dir = dir else { return false }
            lib.load(dir)
            return true
        }, isTargeted: { dropping = $0 })
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 4)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { lib.chooseFolder() } label: { Label("Open", systemImage: "folder") }
                Picker("Sort", selection: $lib.sort) {
                    ForEach(SortKey.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                Menu {
                    ForEach(0..<6) { n in
                        Button(n == 0 ? "All files" : "\(n)★ and up") { lib.minRating = n }
                    }
                } label: {
                    Label("Rating filter", systemImage: lib.minRating > 0 ? "star.fill" : "star")
                }
                Toggle(isOn: $lib.includeSubfolders) {
                    Label("Include subfolders", systemImage: "square.stack.3d.down.right")
                }
                .toggleStyle(.button)
                .help("Show files from all subfolders in one flat view")
                Toggle(isOn: $lib.showPaths) {
                    Label("Show paths", systemImage: "text.alignleft")
                }
                .toggleStyle(.button)
                .help("Show or hide file and folder paths")
                Slider(value: $lib.thumbSize, in: 90...700).frame(width: 120)
                Button { lib.showPreview.toggle() } label: { Label("Preview", systemImage: "sidebar.right") }
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var lib: Library

    var body: some View {
        List {
            if let folder = lib.folder {
                Section("Current folder") {
                    Label(lib.inBin ? "Review Bin" : folder.lastPathComponent,
                          systemImage: lib.inBin ? "trash.fill" : "folder.fill")
                        .foregroundColor(.accentColor)
                        .help(folder.path)
                    let parent = folder.deletingLastPathComponent()
                    Button { lib.load(parent) } label: {
                        Label(lib.inBin ? "Back to folder" : "Up one level", systemImage: "arrow.turn.left.up")
                    }
                    .buttonStyle(.plain)
                    .dropDestination(for: URL.self) { urls, _ in
                        lib.move(urls, to: parent); return true
                    }
                }
                Section("Subfolders (drop files here)") {
                    ForEach(lib.subfolders, id: \.self) { dir in
                        Button { lib.load(dir) } label: {
                            Label(dir.lastPathComponent, systemImage: "folder")
                        }
                        .buttonStyle(.plain)
                        .dropDestination(for: URL.self) { urls, _ in
                            lib.move(urls, to: dir); return true
                        }
                    }
                    Button { lib.newFolder() } label: {
                        Label("New folder…", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
                if lib.root != nil {
                    Section("Review") {
                        Button { lib.openBin() } label: {
                            Label(lib.binCount > 0 ? "Review Bin (\(lib.binCount))" : "Review Bin",
                                  systemImage: lib.binCount > 0 ? "trash.fill" : "trash")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section("Recent") {
                ForEach(lib.recents, id: \.self) { url in
                    Button { lib.load(url) } label: {
                        Label(url.lastPathComponent, systemImage: "clock")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Thumbnail grid

struct GridPane: View {
    @EnvironmentObject var lib: Library

    private func cols(_ w: CGFloat) -> Int {
        max(1, Int((w - 24 + 12) / (lib.thumbSize + 8 + 12)))
    }

    var body: some View {
        VStack(spacing: 0) {
            if lib.inBin {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                    Text("Review Bin: nothing here is deleted yet").font(.callout)
                    Spacer()
                    Button("Restore") { lib.restoreSelection() }
                        .disabled(lib.selection.isEmpty)
                    Button("Delete Permanently…") { lib.deleteSelectionPermanently() }
                        .disabled(lib.selection.isEmpty)
                    Button("Send All to Finder Trash…") { lib.emptyBin() }
                        .disabled(lib.items.isEmpty)
                }
                .padding(8)
                .background(Color.orange.opacity(0.15))
                Divider()
            }
            TypeFilterBar()
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: lib.thumbSize + 8, maximum: lib.thumbSize + 8), spacing: 12)],
                            spacing: 12
                        ) {
                            ForEach(lib.visible) { item in
                                CellView(item: item).id(item.id)
                            }
                        }
                        .padding(12)
                    }
                    .onChange(of: lib.primary) { id in
                        if let id = id { proxy.scrollTo(id) }
                    }
                }
                .onAppear { lib.columns = cols(geo.size.width) }
                .onChange(of: geo.size.width) { w in lib.columns = cols(w) }
                .onChange(of: lib.thumbSize) { _ in lib.columns = cols(geo.size.width) }
            }
            Divider()
            HStack {
                Text("\(lib.visible.count) items")
                if !lib.selection.isEmpty { Text("· \(lib.selection.count) selected") }
                if lib.showPaths {
                    Text("·")
                    Text((lib.primaryItem?.url.deletingLastPathComponent() ?? lib.folder)?.path ?? "")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer()
                Text(lib.status).lineLimit(1)
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }
}

struct CellView: View {
    let item: FileItem
    @EnvironmentObject var lib: Library

    private var selected: Bool { lib.selection.contains(item.id) }

    var body: some View {
        VStack(spacing: 4) {
            ThumbView(url: item.url, points: lib.thumbSize, modified: item.modified)
                .frame(width: lib.thumbSize, height: lib.thumbSize)
                .background(Color.gray.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 3)
                )
            Text(item.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            if lib.showPaths {
                let rel = lib.relativeFolder(item)
                Text(rel.isEmpty ? "—" : rel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Text(item.rating > 0 ? String(repeating: "★", count: item.rating) : " ")
                .font(.caption2)
                .foregroundColor(.yellow)
        }
        .help(item.url.path)
        .padding(4)
        .background(selected ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { lib.open(item) }
        .onTapGesture { lib.click(item) }
        .draggable(item.url)
        .contextMenu {
            Button("Quick Look") { lib.selectIfNeeded(item); lib.quickLook() }
            Button("Open") { lib.open(item) }
            Button("Reveal in Finder") { lib.reveal(lib.targetURLs(for: item)) }
            Menu("Rate") {
                ForEach(0..<6) { n in
                    Button(n == 0 ? "No rating" : String(repeating: "★", count: n)) {
                        lib.setRating(n, for: lib.targetURLs(for: item))
                    }
                }
            }
            if lib.inBin {
                Divider()
                Button("Restore") { lib.selectIfNeeded(item); lib.restoreSelection() }
                Button("Delete Permanently…") { lib.selectIfNeeded(item); lib.deleteSelectionPermanently() }
            } else {
                Menu("Move to") {
                    if let parent = lib.folder?.deletingLastPathComponent() {
                        Button("↑ Parent folder") { lib.move(lib.targetURLs(for: item), to: parent) }
                    }
                    ForEach(lib.subfolders, id: \.self) { d in
                        Button(d.lastPathComponent) { lib.move(lib.targetURLs(for: item), to: d) }
                    }
                }
                Divider()
                Button("Move to Trash") {
                    lib.selectIfNeeded(item)
                    lib.trashSelection()
                }
            }
        }
    }
}

struct ThumbView: View {
    let url: URL
    let points: CGFloat
    let modified: Date
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: "\(url.path)|\(Int((points / 64).rounded(.up)))|\(modified.timeIntervalSince1970)") {
            image = await Thumbs.shared.image(for: url, points: points, modified: modified)
        }
    }
}

// MARK: - Large preview + info

struct PreviewPane: View {
    @EnvironmentObject var lib: Library

    var body: some View {
        VStack(spacing: 0) {
            if let item = lib.primaryItem {
                ThumbView(url: item.url, points: 1200, modified: item.modified)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .underPageBackgroundColor))
                Divider()
                InfoPanel(item: item)
            } else {
                Text("Select a file to preview")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct InfoPanel: View {
    let item: FileItem
    @EnvironmentObject var lib: Library
    @State private var newTag = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.name).font(.headline).lineLimit(1).truncationMode(.middle)
            if lib.selection.count > 1 {
                Text("\(lib.selection.count) files selected: rating and tags apply to all")
                    .font(.caption).foregroundColor(.accentColor)
            }
            Text("\(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file)) · \(item.ext.uppercased()) · \(item.modified.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundColor(.secondary)

            if lib.showPaths {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "folder").foregroundColor(.secondary)
                    Text(item.url.deletingLastPathComponent().path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button("Copy") { lib.copyPath(item.url) }
                        .controlSize(.small)
                }
            }

            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { n in
                    Image(systemName: n <= item.rating ? "star.fill" : "star")
                        .foregroundColor(.yellow)
                        .onTapGesture { lib.setRating(n == item.rating ? 0 : n) }
                }
                Text("(keys 0–5)").font(.caption2).foregroundColor(.secondary)
                    .padding(.leading, 4)
            }

            FlowLayout(spacing: 6) {
                ForEach(item.tags, id: \.self) { tag in
                    let label = Library.label(tag)
                    HStack(spacing: 5) {
                        if let c = finderTagColor(Library.colorIndex(tag)) {
                            Circle().fill(c).frame(width: 8, height: 8)
                        }
                        Text(label).font(.caption).lineLimit(1)
                        Button { lib.removeTag(label) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.gray.opacity(0.18)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Add tag, press Return", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .onSubmit { lib.addTag(newTag); newTag = "" }

            HStack {
                Button("Quick Look") { lib.quickLook() }
                Button("Open") { lib.open(item) }
                Button("Reveal in Finder") { lib.reveal([item.url]) }
                Spacer()
                if lib.inBin {
                    Button("Restore") { lib.restoreSelection() }
                } else {
                    Button(role: .destructive) { lib.trashSelection() } label: {
                        Label("Trash", systemImage: "trash")
                    }
                }
            }
        }
        .padding(12)
    }
}


// MARK: - File-type chips

struct TypeFilterBar: View {
    @EnvironmentObject var lib: Library

    var body: some View {
        let counts = lib.typeCounts
        if counts.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("All", count: lib.items.count, on: lib.typeFilter.isEmpty) { lib.typeFilter = [] }
                    ForEach(counts) { c in
                        chip(c.title, count: c.count, on: lib.typeFilter.contains(c.kind)) { lib.toggleType(c.kind) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
            Divider()
        }
    }

    private func chip(_ title: String, count: Int, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).fontWeight(.medium)
                Text("\(count)").foregroundColor(on ? Color.white.opacity(0.8) : Color.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(on ? Color.accentColor : Color.gray.opacity(0.18)))
            .foregroundColor(on ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}
