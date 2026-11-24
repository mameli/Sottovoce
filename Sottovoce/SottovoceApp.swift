import SwiftUI

@main
struct SottovoceApp: App {
    @State private var store = QueueStore()

    init() {
        TerminalCommand.runIfRequested()
    }

    var body: some Scene {
        WindowGroup("Sottovoce") {
            ContentView(store: store)
        }
        .defaultSize(width: 620, height: 460)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Add Media Files…") {
                    store.openFilePicker()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
