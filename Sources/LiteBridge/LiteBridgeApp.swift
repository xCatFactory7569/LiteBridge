import SwiftUI

@main
struct LiteBridgeApp: App {
    @StateObject private var lib = Library()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(lib)
                .frame(minWidth: 900, minHeight: 560)
                .onOpenURL { url in lib.openExternal(url) }
        }
        .handlesExternalEvents(matching: Set(["*"]))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder…") { lib.chooseFolder() }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { lib.undo() }
                    .keyboardShortcut("z")
            }
            CommandMenu("Library") {
                Button("Refresh") { lib.refresh() }
                    .keyboardShortcut("r")
                Button("New Folder…") { lib.newFolder() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("Move to Trash") { lib.trashSelection() }
                    .keyboardShortcut(.delete, modifiers: .command)
                Button("Open Review Bin") { lib.openBin() }
                    .keyboardShortcut("b", modifiers: [.command, .shift])
                Toggle("Deleting uses the Review Bin (off = Finder Trash)", isOn: $lib.useBin)
            }
        }
    }
}
