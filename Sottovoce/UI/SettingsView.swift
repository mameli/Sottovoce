import SottovoceCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ModelsSettingsTab()
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }
        }
        .frame(width: 480, height: 260)
    }
}

private struct ModelsSettingsTab: View {
    @State private var parakeet: ModelLocator.Found?
    @State private var sileroOwner: ModelLocator.Owner?
    @State private var ownParakeetExists = false
    @State private var isDownloading = false
    @State private var downloadStatus: String?

    private var locator: ModelLocator {
        ModelLocator.standard(applicationSupport: .applicationSupportDirectory)
    }

    var body: some View {
        Form {
            Section("Speech recognition") {
                LabeledContent("Parakeet") {
                    if let parakeet {
                        let source = parakeet.owner.name == "Sottovoce"
                            ? "downloaded by Sottovoce"
                            : "from \(parakeet.owner.name)"
                        Text("\(parakeet.model.displayName) (\(source))")
                            .foregroundStyle(.primary)
                    } else if let downloadStatus {
                        Text(downloadStatus)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not downloaded (downloads at first use)")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    if parakeet == nil {
                        Button("Download Parakeet Ultra") {
                            downloadParakeet()
                        }
                        .disabled(isDownloading)
                    }
                    if ownParakeetExists {
                        Button("Delete Sottovoce's Copy", role: .destructive) {
                            deleteOwnParakeet()
                        }
                        .disabled(isDownloading)
                    }
                    Spacer()
                    Button("Refresh") {
                        refresh()
                    }
                    .disabled(isDownloading)
                }
            }

            Section("Speech detection") {
                LabeledContent("Silero VAD") {
                    if let sileroOwner {
                        let source = sileroOwner.name == "Sottovoce"
                            ? "downloaded by Sottovoce"
                            : "from \(sileroOwner.name)"
                        Text("Silero VAD (\(source))")
                    } else {
                        Text("Not downloaded (downloads at first use)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        let fm = FileManager.default
        let exists: (URL) -> Bool = { fm.fileExists(atPath: $0.path(percentEncoded: false)) }
        parakeet = locator.candidates(fileExists: exists).first
        sileroOwner = locator.sileroCandidates(fileExists: exists).first
        ownParakeetExists = exists(locator.ownFolder(for: .ultra))
    }

    private func downloadParakeet() {
        isDownloading = true
        downloadStatus = "Downloading Parakeet Ultra…"
        Task {
            do {
                _ = try await Transcriber.load { message in
                    Task { @MainActor in downloadStatus = message }
                }
                downloadStatus = nil
            } catch {
                downloadStatus = "\(error)"
            }
            isDownloading = false
            refresh()
        }
    }

    private func deleteOwnParakeet() {
        try? FileManager.default.removeItem(at: locator.ownFolder(for: .ultra))
        refresh()
    }
}
