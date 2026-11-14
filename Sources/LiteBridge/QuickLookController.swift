import AppKit
import Quartz

/// Space-bar Quick Look, works even when the preview pane is hidden.
final class QuickLookController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLookController()

    private var urls: [URL] = []
    private var onSync: ((URL) -> Void)?
    private var observers: [NSObjectProtocol] = []

    func toggle(urls: [URL], current: URL?, onSync: @escaping (URL) -> Void) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if panel.isVisible {
            sync(panel)
            panel.orderOut(nil)
            return
        }
        guard !urls.isEmpty else { return }
        self.urls = urls
        self.onSync = onSync
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = current.flatMap { urls.firstIndex(of: $0) } ?? 0
        panel.makeKeyAndOrderFront(nil)

        if observers.isEmpty {
            for name in [NSWindow.willCloseNotification, NSWindow.didResignKeyNotification] {
                let o = NotificationCenter.default.addObserver(forName: name, object: panel, queue: .main) { [weak self] _ in
                    self?.sync(panel)
                }
                observers.append(o)
            }
        }
    }

    /// Keeps the app's selection on whichever file you ended on in Quick Look.
    private func sync(_ panel: QLPreviewPanel) {
        let i = panel.currentPreviewItemIndex
        if urls.indices.contains(i) { onSync?(urls[i]) }
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        urls[index] as NSURL
    }
}
