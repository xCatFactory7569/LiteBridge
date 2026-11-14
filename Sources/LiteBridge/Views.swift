import SwiftUI
import AppKit

// MARK: - Main layout

struct ContentView: View {
    @EnvironmentObject var lib: Library

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 170, ideal: 220, max: 340)
        } detail: {
            if lib.folder == nil {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 48)).foregroundColor(.secondary)
                    Text("Open a folder to start").font(.title3)
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
        .navigationTitle(lib.folder?.lastPathComponent ?? "LiteBridge")
        .searchable(text: $lib.search, prompt: "Filter by name or tag")
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
                Slider(value: $lib.thumbSize, in: 90...360).frame(width: 110)
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
                    Label(folder.lastPathComponent, systemImage: "folder.fill")
                        .foregroundColor(.accentColor)
                    let parent = folder.deletingLastPathComponent()
                    Button { lib.load(parent) } label: {
                        Label("Up one level", systemImage: "arrow.turn.left.up")
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
            Text(item.rating > 0 ? String(repeating: "★", count: item.rating) : " ")
                .font(.caption2)
                .foregroundColor(.yellow)
        }
        .padding(4)
        .background(selected ? Color.accentColor.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { lib.open(item) }
        .onTapGesture { lib.click(item) }
        .draggable(item.url)
        .contextMenu {
            Button("Open") { lib.open(item) }
            Button("Reveal in Finder") { lib.reveal(lib.targetURLs(for: item)) }
            Menu("Rate") {
                ForEach(0..<6) { n in
                    Button(n == 0 ? "No rating" : String(repeating: "★", count: n)) {
                        lib.setRating(n, for: lib.targetURLs(for: item))
                    }
                }
            }
            Menu("Move to") {
                let parent = lib.folder?.deletingLastPathComponent()
                if let parent = parent {
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

            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { n in
                    Image(systemName: n <= item.rating ? "star.fill" : "star")
                        .foregroundColor(.yellow)
                        .onTapGesture { lib.setRating(n == item.rating ? 0 : n) }
                }
                Text("(keys 0–5)").font(.caption2).foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(item.tags, id: \.self) { tag in
                    let label = Library.label(tag)
                    HStack(spacing: 4) {
                        Text(label).font(.caption).lineLimit(1)
                        Button { lib.removeTag(label) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                }
            }

            TextField("Add tag, press Return", text: $newTag)
                .textFieldStyle(.roundedBorder)
                .onSubmit { lib.addTag(newTag); newTag = "" }

            HStack {
                Button("Open") { lib.open(item) }
                Button("Reveal in Finder") { lib.reveal([item.url]) }
                Spacer()
                Button(role: .destructive) { lib.trashSelection() } label: {
                    Label("Trash", systemImage: "trash")
                }
            }
        }
        .padding(12)
    }
}
