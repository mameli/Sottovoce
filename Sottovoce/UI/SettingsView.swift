import AppKit
import SottovoceCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ModelsSettingsTab()
                .tabItem {
                    Label("Models", systemImage: "cpu")
                }
            VocabularySettingsTab()
                .tabItem {
                    Label("Vocabulary", systemImage: "character.book.closed")
                }
        }
        .frame(width: 520, height: 340)
    }
}

private struct ModelsSettingsTab: View {
    @State private var parakeet: ModelLocator.Found?
    @State private var sileroOwner: ModelLocator.Owner?
    @State private var nemotronOwner: ModelLocator.Owner?
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

            Section("Speech detection & Speakers") {
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

                LabeledContent("Speakers") {
                    if let nemotronOwner {
                        let source = nemotronOwner.name == "Sottovoce"
                            ? "downloaded by Sottovoce"
                            : "from \(nemotronOwner.name)"
                        Text("Nemotron 3 (\(source))")
                    } else {
                        Text("Not downloaded (downloads when Speakers is enabled)")
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
        nemotronOwner = locator.nemotronCandidates(fileExists: exists).first
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

private struct VocabularySettingsTab: View {
    @State private var text = ""
    @State private var status: String?

    private var url: URL { Vocabulary.defaultURL }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Terms and misheard variants applied to every Transcript (`~/.sottovoce/vocabulary.md`).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.secondary.opacity(0.25))
                )

            HStack {
                let count = Vocabulary(fileContent: text).entries.count
                Text(status ?? "\(count) \(count == 1 ? "entry" : "entries")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reveal in Finder") {
                    ensureFileExists()
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .onAppear(perform: load)
    }

    private func load() {
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            text = existing
        } else {
            text = Vocabulary.exampleFileContent
        }
        status = nil
    }

    private func ensureFileExists() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path(percentEncoded: false)) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: url, options: .atomic)
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
            let count = Vocabulary(fileContent: text).entries.count
            status = "Saved (\(count) \(count == 1 ? "entry" : "entries"))"
        } catch {
            status = "Could not save: \(error.localizedDescription)"
        }
    }
}
