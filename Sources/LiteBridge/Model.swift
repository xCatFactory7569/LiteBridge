import SwiftUI
import AppKit
import QuickLookThumbnailing

// MARK: - Data types

struct FileItem: Identifiable, Hashable {
    let url: URL
    var rating: Int
    var tags: [String]
    var size: Int
    var modified: Date

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var ext: String { url.pathExtension.lowercased() }
}

enum SortKey: String, CaseIterable, Identifiable {
    case name = "Name"
    case type = "Type"
    case date = "Date modified"
    case size = "Size"
    case rating = "Rating"
    var id: String { rawValue }
}

// MARK: - Extended attributes (used for star ratings)

enum XAttr {
    static func get(_ name: String, _ url: URL) -> Data? {
        url.path.withCString { p -> Data? in
            let size = getxattr(p, name, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var data = Data(count: size)
            let n = data.withUnsafeMutableBytes { getxattr(p, name, $0.baseAddress, size, 0, 0) }
            return n >= 0 ? data : nil
        }
    }

    static func set(_ name: String, _ data: Data, _ url: URL) {
        url.path.withCString { p in
            _ = data.withUnsafeBytes { setxattr(p, name, $0.baseAddress, data.count, 0, 0) }
        }
    }

    static func remove(_ name: String, _ url: URL) {
        url.path.withCString { p in
            _ = removexattr(p, name, 0)
        }
    }
}

// MARK: - Thumbnails (macOS Quick Look: handles PSD, AI, PDF, JPG, RAW...)

final class Thumbs {
    static let shared = Thumbs()
    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 600
        return c
    }()

    func image(for url: URL, points: CGFloat, modified: Date) async -> NSImage? {
        let bucket = (points / 64).rounded(.up) * 64
        let key = "\(url.path)|\(Int(bucket))|\(modified.timeIntervalSince1970)" as NSString
        if let hit = cache.object(forKey: key) { return hit }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: bucket, height: bucket),
            scale: 2,
            representationTypes: .all
        )
        do {
            let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            let img = rep.nsImage
            cache.setObject(img, forKey: key)
            return img
        } catch {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
    }
}

// MARK: - Library (all app state + file operations)

final class Library: ObservableObject {
    @Published var folder: URL?
    @Published var items: [FileItem] = []
    @Published var subfolders: [URL] = []
    @Published var selection: Set<URL> = []
    @Published var primary: URL?
    @Published var search = ""
    @Published var minRating = 0
    @Published var sort: SortKey = .name
    @Published var thumbSize: CGFloat = 190
    @Published var showPreview = true
    @Published var recents: [URL] = []
    @Published var status = ""
    @Published var root: URL?
    @Published var binCount = 0
    @Published var useBin = true {
        didSet { UserDefaults.standard.set(useBin, forKey: "useBin") }
    }

    static let binName = "_LiteBridge Bin"
    private var skipConfirm = false   // resets every launch ("until I quit")

    var columns = 4
    private var anchor: URL?
    private var undoStack: [[(current: URL, original: URL)]] = []
    private var monitor: Any?
    private let fm = FileManager.default

    private static let ratingKey = "com.apple.metadata:kMDItemStarRating"

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "recents") ?? []
        recents = saved.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        useBin = UserDefaults.standard.object(forKey: "useBin") as? Bool ?? true
        if let last = recents.first { load(last, remember: false) }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            return self.handleKey(event)
        }
    }

    // MARK: Derived

    var visible: [FileItem] {
        var r = items
        if minRating > 0 { r = r.filter { $0.rating >= minRating } }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            r = r.filter { $0.name.lowercased().contains(q) || $0.tags.contains { $0.lowercased().contains(q) } }
        }
        func byName(_ a: FileItem, _ b: FileItem) -> Bool {
            a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        switch sort {
        case .name: r.sort(by: byName)
        case .type: r.sort { $0.ext == $1.ext ? byName($0, $1) : $0.ext < $1.ext }
        case .date: r.sort { $0.modified > $1.modified }
        case .size: r.sort { $0.size > $1.size }
        case .rating: r.sort { $0.rating == $1.rating ? byName($0, $1) : $0.rating > $1.rating }
        }
        return r
    }

    var primaryItem: FileItem? {
        guard let p = primary else { return nil }
        return items.first { $0.id == p }
    }

    // MARK: Loading

    func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true
        p.canChooseFiles = false
        p.allowsMultipleSelection = false
        p.prompt = "Open"
        if p.runModal() == .OK, let u = p.url { load(u) }
    }

    func load(_ url: URL, remember: Bool = true) {
        folder = url
        let path = url.standardizedFileURL.path
        var inside = false
        if let r = root?.standardizedFileURL.path { inside = (path == r || path.hasPrefix(r + "/")) }
        if !inside { root = url }
        selection = []
        primary = nil
        anchor = nil
        search = ""
        if remember {
            recents.removeAll { $0 == url }
            recents.insert(url, at: 0)
            recents = Array(recents.prefix(8))
            UserDefaults.standard.set(recents.map { $0.path }, forKey: "recents")
        }
        refresh()
    }

    func refresh() {
        guard let folder = folder else { return }
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let urls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        var files: [FileItem] = []
        var dirs: [URL] = []
        for u in urls {
            let v = try? u.resourceValues(forKeys: Set(keys))
            if v?.isDirectory == true {
                dirs.append(u)
                continue
            }
            files.append(FileItem(
                url: u,
                rating: Self.readRating(u),
                tags: Self.readTags(u),
                size: v?.fileSize ?? 0,
                modified: v?.contentModificationDate ?? .distantPast
            ))
        }
        items = files
        subfolders = dirs.filter { $0.lastPathComponent != Self.binName }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let ids = Set(files.map { $0.url })
        selection = selection.intersection(ids)
        if let p = primary, !ids.contains(p) { primary = selection.first }
        updateBinCount()
    }

    /// Called when a folder is dropped on the window / Dock icon / "Open With".
    func openExternal(_ url: URL) {
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        if isDir {
            load(url)
        } else {
            load(url.deletingLastPathComponent())
            selectOnly(url)
        }
    }

    // MARK: Selection

    func click(_ item: FileItem) {
        let flags = NSEvent.modifierFlags
        let v = visible
        if flags.contains(.shift), let a = anchor,
           let i1 = v.firstIndex(where: { $0.id == a }),
           let i2 = v.firstIndex(where: { $0.id == item.id }) {
            selection = Set(v[min(i1, i2)...max(i1, i2)].map { $0.id })
            primary = item.id
        } else if flags.contains(.command) {
            if selection.contains(item.id) {
                selection.remove(item.id)
                primary = selection.first
            } else {
                selection.insert(item.id)
                primary = item.id
            }
            anchor = item.id
        } else {
            selection = [item.id]
            primary = item.id
            anchor = item.id
        }
    }

    func selectIfNeeded(_ item: FileItem) {
        if !selection.contains(item.id) {
            selection = [item.id]
            primary = item.id
            anchor = item.id
        }
    }

    func targetURLs(for item: FileItem) -> [URL] {
        selection.contains(item.id) ? Array(selection) : [item.id]
    }

    func moveSelection(dx: Int, dy: Int, extend: Bool) {
        let v = visible
        guard !v.isEmpty else { return }
        guard let p = primary, let idx = v.firstIndex(where: { $0.id == p }) else {
            selection = [v[0].id]; primary = v[0].id; anchor = v[0].id
            return
        }
        let step = dx + dy * max(columns, 1)
        let n = min(max(idx + step, 0), v.count - 1)
        if extend {
            let a = anchor ?? p
            if let ai = v.firstIndex(where: { $0.id == a }) {
                selection = Set(v[min(ai, n)...max(ai, n)].map { $0.id })
            }
        } else {
            selection = [v[n].id]
            anchor = v[n].id
        }
        primary = v[n].id
    }

    // MARK: Keyboard

    private func handleKey(_ e: NSEvent) -> NSEvent? {
        guard folder != nil else { return e }
        if NSApp.keyWindow is NSPanel { return e }
        if let r = NSApp.keyWindow?.firstResponder, r is NSText { return e }
        let mods = e.modifierFlags.intersection([.command, .option, .control])
        guard mods.isEmpty else { return e }
        let shift = e.modifierFlags.contains(.shift)

        switch e.keyCode {
        case 123: moveSelection(dx: -1, dy: 0, extend: shift); return nil
        case 124: moveSelection(dx: 1, dy: 0, extend: shift); return nil
        case 125: moveSelection(dx: 0, dy: 1, extend: shift); return nil
        case 126: moveSelection(dx: 0, dy: -1, extend: shift); return nil
        case 49: quickLook(); return nil
        case 51, 117: trashSelection(); return nil
        case 36: openSelection(); return nil
        default: break
        }
        if !shift, let ch = e.charactersIgnoringModifiers, ch.count == 1,
           let n = Int(ch), (0...5).contains(n), !selection.isEmpty {
            setRating(n)
            return nil
        }
        return e
    }

    // MARK: Actions

    func open(_ item: FileItem) { NSWorkspace.shared.open(item.url) }

    func openSelection() {
        for u in selection { NSWorkspace.shared.open(u) }
    }

    func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    // MARK: Trash / Review Bin

    var binURL: URL? { root?.appendingPathComponent(Self.binName) }

    var inBin: Bool {
        guard let f = folder, let b = binURL else { return false }
        return f.standardizedFileURL.path == b.standardizedFileURL.path
    }

    private var originsURL: URL? { binURL?.appendingPathComponent(".origins.json") }

    private func readOrigins() -> [String: String] {
        guard let u = originsURL, let d = try? Data(contentsOf: u),
              let m = try? JSONDecoder().decode([String: String].self, from: d) else { return [:] }
        return m
    }

    private func writeOrigins(_ m: [String: String]) {
        guard let u = originsURL, let d = try? JSONEncoder().encode(m) else { return }
        try? d.write(to: u)
    }

    private func recordOrigin(binFile: String, original: URL) {
        var m = readOrigins()
        let rp = root?.standardizedFileURL.path ?? ""
        let op = original.standardizedFileURL.path
        m[binFile] = op.hasPrefix(rp + "/") ? String(op.dropFirst(rp.count + 1)) : op
        writeOrigins(m)
    }

    func updateBinCount() {
        guard let b = binURL else { binCount = 0; return }
        binCount = ((try? fm.contentsOfDirectory(at: b, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []).count
    }

    func openBin() {
        guard let b = binURL else { return }
        try? fm.createDirectory(at: b, withIntermediateDirectories: true)
        load(b, remember: false)
    }

    private func confirmTrash(count: Int, name: String) -> Bool {
        if skipConfirm { return true }
        let dest = useBin ? "the Review Bin" : "the Trash"
        let alert = NSAlert()
        alert.messageText = count == 1 ? "Move “\(name)” to \(dest)?" : "Move \(count) files to \(dest)?"
        alert.informativeText = useBin
            ? "Nothing is deleted yet. You can review or restore files from the Review Bin, or press ⌘Z."
            : "You can restore files from the Finder Trash, or press ⌘Z."
        alert.addButton(withTitle: "Move")
        alert.addButton(withTitle: "Cancel")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Don’t ask again until I quit LiteBridge"
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        if alert.suppressionButton?.state == .on { skipConfirm = true }
        return true
    }

    func trashSelection() {
        if inBin { deleteSelectionPermanently(); return }
        let v = visible
        let targets = v.filter { selection.contains($0.id) }
        guard !targets.isEmpty else { return }
        guard confirmTrash(count: targets.count, name: targets[0].name) else { return }

        let lastIdx = v.lastIndex(where: { selection.contains($0.id) }) ?? 0
        let next = v.dropFirst(lastIdx + 1).first ?? v.last(where: { !selection.contains($0.id) })

        var batch: [(current: URL, original: URL)] = []
        for t in targets {
            do {
                if useBin, let bin = binURL {
                    try fm.createDirectory(at: bin, withIntermediateDirectories: true)
                    let dest = uniqueURL(bin.appendingPathComponent(t.url.lastPathComponent))
                    try fm.moveItem(at: t.url, to: dest)
                    recordOrigin(binFile: dest.lastPathComponent, original: t.url)
                    batch.append((dest, t.url))
                } else {
                    var out: NSURL?
                    try fm.trashItem(at: t.url, resultingItemURL: &out)
                    if let o = out { batch.append((o as URL, t.url)) }
                }
            } catch {
                NSSound.beep()
            }
        }
        if !batch.isEmpty { undoStack.append(batch) }
        selection = []
        primary = nil
        refresh()
        if let n = next, items.contains(where: { $0.id == n.id }) {
            selection = [n.id]; primary = n.id; anchor = n.id
        }
        status = "Moved \(batch.count) to \(useBin ? "the Review Bin" : "the Trash"). Press ⌘Z to undo."
    }

    func restoreSelection() {
        guard let root = root else { return }
        let origins = readOrigins()
        var batch: [(current: URL, original: URL)] = []
        for t in items where selection.contains(t.id) {
            var target = root.appendingPathComponent(t.name)
            if let rel = origins[t.name] {
                target = rel.hasPrefix("/") ? URL(fileURLWithPath: rel) : root.appendingPathComponent(rel)
            }
            try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let dest = uniqueURL(target)
            do {
                try fm.moveItem(at: t.url, to: dest)
                batch.append((dest, t.url))
            } catch {
                NSSound.beep()
            }
        }
        if !batch.isEmpty { undoStack.append(batch) }
        selection = []
        primary = nil
        refresh()
        status = "Restored \(batch.count) file(s) to their original folders."
    }

    func deleteSelectionPermanently() {
        let targets = items.filter { selection.contains($0.id) }
        guard !targets.isEmpty else { return }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = targets.count == 1 ? "Permanently delete “\(targets[0].name)”?" : "Permanently delete \(targets.count) files?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Delete Permanently")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for t in targets { try? fm.removeItem(at: t.url) }
        undoStack = []
        selection = []
        primary = nil
        refresh()
        status = "Permanently deleted \(targets.count) file(s)."
    }

    func emptyBin() {
        guard let b = binURL else { return }
        let all = (try? fm.contentsOfDirectory(at: b, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        guard !all.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Send all \(all.count) files in the Review Bin to the Finder Trash?"
        alert.informativeText = "They stay recoverable from the Finder Trash until you empty it."
        alert.addButton(withTitle: "Send to Finder Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for u in all {
            var out: NSURL?
            try? fm.trashItem(at: u, resultingItemURL: &out)
        }
        if let o = originsURL { try? fm.removeItem(at: o) }
        undoStack = []
        selection = []
        primary = nil
        refresh()
        status = "Sent \(all.count) file(s) to the Finder Trash."
    }

    // MARK: Quick Look

    func quickLook() {
        let v = visible
        guard !v.isEmpty else { return }
        QuickLookController.shared.toggle(urls: v.map { $0.id }, current: primary ?? v[0].id) { [weak self] url in
            self?.selectOnly(url)
        }
    }

    func selectOnly(_ url: URL) {
        guard items.contains(where: { $0.id == url }) else { return }
        selection = [url]
        primary = url
        anchor = url
    }

    func move(_ input: [URL], to dest: URL) {
        var urls = input
        if urls.count == 1, selection.contains(urls[0]) { urls = Array(selection) }
        var batch: [(current: URL, original: URL)] = []
        for u in urls {
            if (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { continue }
            if u.deletingLastPathComponent().standardizedFileURL.path == dest.standardizedFileURL.path { continue }
            let target = uniqueURL(dest.appendingPathComponent(u.lastPathComponent))
            do {
                try fm.moveItem(at: u, to: target)
                batch.append((target, u))
            } catch {
                NSSound.beep()
            }
        }
        if !batch.isEmpty { undoStack.append(batch) }
        refresh()
        status = "Moved \(batch.count) to “\(dest.lastPathComponent)”. Press ⌘Z to undo."
    }

    func undo() {
        guard let batch = undoStack.popLast() else { return }
        var restored: [URL] = []
        for b in batch.reversed() {
            do {
                try fm.moveItem(at: b.current, to: b.original)
                restored.append(b.original)
            } catch {
                NSSound.beep()
            }
        }
        refresh()
        let ids = Set(items.map { $0.id })
        selection = Set(restored.filter { ids.contains($0) })
        primary = selection.first
        status = "Restored \(restored.count) file(s)."
    }

    func newFolder() {
        guard let folder = folder else { return }
        let alert = NSAlert()
        alert.messageText = "New folder"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return }
            try? fm.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: false)
            refresh()
        }
    }

    private func uniqueURL(_ url: URL) -> URL {
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        var i = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    // MARK: Ratings

    func setRating(_ n: Int, for urls: [URL]? = nil) {
        let set = Set(urls ?? Array(selection))
        for u in set { Self.writeRating(n, u) }
        for i in items.indices where set.contains(items[i].url) { items[i].rating = n }
    }

    static func readRating(_ u: URL) -> Int {
        guard let d = XAttr.get(ratingKey, u),
              let v = try? PropertyListSerialization.propertyList(from: d, options: [], format: nil),
              let n = v as? Int else { return 0 }
        return min(max(n, 0), 5)
    }

    static func writeRating(_ n: Int, _ u: URL) {
        if n == 0 {
            XAttr.remove(ratingKey, u)
        } else if let d = try? PropertyListSerialization.data(fromPropertyList: n, format: .binary, options: 0) {
            XAttr.set(ratingKey, d, u)
        }
    }

    // MARK: Tags (real Finder tags, visible in Finder too)

    static func label(_ t: String) -> String {
        String(t.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    static let colorNames: [String: (name: String, index: Int)] = [
        "gray": ("Gray", 1), "grey": ("Gray", 1), "green": ("Green", 2), "purple": ("Purple", 3),
        "blue": ("Blue", 4), "yellow": ("Yellow", 5), "red": ("Red", 6), "orange": ("Orange", 7)
    ]

    /// Finder stores a tag's colour as "Name\n<index>".
    static func colorIndex(_ t: String) -> Int? {
        let parts = t.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        return parts.count > 1 ? Int(parts[1]) : nil
    }

    static func readTags(_ u: URL) -> [String] {
        var v: AnyObject?
        try? (u as NSURL).getResourceValue(&v, forKey: .tagNamesKey)
        return (v as? [String]) ?? []
    }

    static func writeTags(_ tags: [String], _ u: URL) {
        try? (u as NSURL).setResourceValue(tags as NSArray, forKey: .tagNamesKey)
    }

    func addTag(_ raw: String) {
        var t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let c = Self.colorNames[t.lowercased()] { t = "\(c.name)\n\(c.index)" }
        let newLabel = Self.label(t)
        for i in items.indices where selection.contains(items[i].url) {
            let exists = items[i].tags.contains { Self.label($0).caseInsensitiveCompare(newLabel) == .orderedSame }
            if !exists {
                items[i].tags.append(t)
                Self.writeTags(items[i].tags, items[i].url)
            }
        }
    }

    func removeTag(_ label: String) {
        for i in items.indices where selection.contains(items[i].url) {
            let new = items[i].tags.filter { Self.label($0) != label }
            if new.count != items[i].tags.count {
                items[i].tags = new
                Self.writeTags(new, items[i].url)
            }
        }
    }
}
