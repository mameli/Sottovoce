import AppKit
import Foundation
import Observation
import SottovoceCore

/// Drives the GUI's Queue: one Media File subtitled at a time, reusing the loaded `Transcriber`
/// and `SpeechDetector`, and asking before overwriting an existing Subtitle File.
@MainActor
@Observable
final class QueueStore {
    struct Item: Identifiable {
        enum State {
            case pending
            case running(phase: String)
            case completed(SubtitlingResult)
            case failed(String)
            case skipped
        }

        let id = UUID()
        let mediaFile: URL
        var state: State = .pending

        var fileName: String { mediaFile.lastPathComponent }
    }

    enum OverwriteDecision {
        case replace
        case replaceAll
        case skip
    }

    struct OverwritePrompt: Identifiable {
        let id = UUID()
        let fileName: String
        let continuation: CheckedContinuation<OverwriteDecision, Never>
    }

    var items: [Item] = []
    var style: Style = .classic
    var words: Int = 1
    var format: Format = .srt
    var speakers = false
    /// Target language code for Classic Translation (macOS 26+); empty string means no translation.
    var translateLanguage = ""
    var isRunning = false
    var statusMessage: String?
    var overwritePrompt: OverwritePrompt?

    @ObservationIgnored private var transcriber: Transcriber?
    @ObservationIgnored private let speechDetector = SpeechDetector()
    @ObservationIgnored private let speakerDiarizer = SpeakerDiarizer()
    @ObservationIgnored private var runTask: Task<Void, Never>?

    var hasPendingWork: Bool {
        items.contains { item in
            switch item.state {
            case .pending, .failed, .skipped: true
            case .running, .completed: false
            }
        }
    }

    var hasCompleted: Bool {
        items.contains {
            if case .completed = $0.state { return true }
            return false
        }
    }

    func addFiles(_ urls: [URL]) {
        let existing = Set(items.map { $0.mediaFile.standardizedFileURL.path(percentEncoded: false) })
        var seen = existing
        for url in urls {
            let standardized = url.standardizedFileURL
            let path = standardized.path(percentEncoded: false)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  !isDirectory.boolValue,
                  seen.insert(path).inserted
            else { continue }
            items.append(Item(mediaFile: standardized))
        }
    }

    func remove(_ item: Item) {
        guard case .running = item.state else {
            items.removeAll { $0.id == item.id }
            return
        }
    }

    func clearCompleted() {
        items.removeAll {
            if case .completed = $0.state { return true }
            return false
        }
    }

    func clearAll() {
        guard !isRunning else { return }
        items.removeAll()
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
    }

    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Choose video or audio files to subtitle."
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    func resolveOverwrite(_ decision: OverwriteDecision) {
        let prompt = overwritePrompt
        overwritePrompt = nil
        prompt?.continuation.resume(returning: decision)
    }

    func start() {
        guard !isRunning, hasPendingWork else { return }
        isRunning = true
        let currentStyle = style
        let currentWords = words
        let currentFormat = format
        let currentSpeakers = speakers
        let currentTranslate = (currentStyle == .classic && !translateLanguage.isEmpty) ? translateLanguage : nil
        let options = Command.Options(
            force: true,
            style: currentStyle,
            words: currentWords,
            format: currentFormat,
            speakers: currentSpeakers,
            translate: currentTranslate
        )

        runTask = Task { [self] in
            defer {
                isRunning = false
                runTask = nil
            }
            var replaceAll = false
            for index in items.indices {
                if Task.isCancelled { break }
                switch items[index].state {
                case .completed, .running:
                    continue
                case .pending, .failed, .skipped:
                    break
                }

                let mediaFile = items[index].mediaFile
                let output = SubtitleFile.url(for: mediaFile, format: currentFormat)
                let translationOutput = currentTranslate.map {
                    SubtitleFile.url(for: mediaFile, format: currentFormat, language: $0)
                }
                let existingFile: URL? = if FileManager.default.fileExists(atPath: output.path(percentEncoded: false)) {
                    output
                } else if let translationOutput, FileManager.default.fileExists(atPath: translationOutput.path(percentEncoded: false)) {
                    translationOutput
                } else {
                    nil
                }
                if !replaceAll, let existingFile {
                    let decision = await askOverwrite(fileName: existingFile.lastPathComponent)
                    switch decision {
                    case .replace:
                        break
                    case .replaceAll:
                        replaceAll = true
                    case .skip:
                        items[index].state = .skipped
                        continue
                    }
                }

                let itemID = items[index].id
                setState(id: itemID, state: .running(phase: transcriber == nil ? "Loading model…" : "Starting…"))

                do {
                    if transcriber == nil {
                        let loaded = try await Transcriber.load { [weak self] message in
                            Task { @MainActor in
                                self?.statusMessage = message
                                self?.setState(id: itemID, state: .running(phase: message))
                            }
                        }
                        transcriber = loaded
                        statusMessage = "\(loaded.model.model.displayName) (from \(loaded.model.owner.name))"
                    }
                    let result = try await Subtitling.subtitleOne(
                        mediaFile,
                        output: output,
                        with: transcriber!,
                        speechDetector: speechDetector,
                        speakerDiarizer: currentSpeakers ? speakerDiarizer : nil,
                        options: options,
                        onPhase: { [weak self] phase in
                            Task { @MainActor in
                                self?.setState(id: itemID, state: .running(phase: phase))
                            }
                        }
                    )
                    setState(id: itemID, state: .completed(result))
                } catch {
                    if Task.isCancelled {
                        setState(id: itemID, state: .pending)
                        break
                    }
                    setState(id: itemID, state: .failed("\(error)"))
                }
            }
        }
    }

    func cancel() {
        runTask?.cancel()
    }

    private func setState(id: UUID, state: Item.State) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].state = state
        }
    }

    private func askOverwrite(fileName: String) async -> OverwriteDecision {
        await withCheckedContinuation { continuation in
            overwritePrompt = OverwritePrompt(fileName: fileName, continuation: continuation)
        }
    }
}
