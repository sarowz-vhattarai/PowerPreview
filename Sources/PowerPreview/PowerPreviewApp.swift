import SwiftUI

@main
struct PowerPreviewApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 760, minHeight: 520)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Folder...") {
                    appState.openFolder()
                }
                .keyboardShortcut("o", modifiers: [.command])
            }
        }
    }
}
