import SwiftUI

@main
struct SottovoceApp: App {
    init() {
        TerminalCommand.runIfRequested()
    }

    var body: some Scene {
        WindowGroup("Sottovoce") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

/// Placeholder until the GUI milestone (M2): the window only says how to use the CLI.
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "captions.bubble")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Sottovoce")
                .font(.title)
            Text("For now, use the command line: sottovoce <video>")
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 420, minHeight: 260)
    }
}
