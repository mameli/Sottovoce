import AVFoundation
import Foundation
import NaturalLanguage
import SottovoceCore

/// `sottovoce <media-file>...`: subtitles each Media File in turn, the Queue of the CLI. Progress
/// goes to stderr; stdout gets only the path of each Subtitle File written (or a JSON array with
/// `--json`), so an agent can read it cleanly.
enum Subtitling {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run(_ mediaFiles: [String], options: Command.Options) async -> Int32 {
        var transcriber: Transcriber?
        let speechDetector = SpeechDetector { progress($0) }
        let speakerDiarizer = SpeakerDiarizer()
        var results: [SubtitlingResult] = []
        var failed = false
        var modelFailure: Error?

        for path in mediaFiles {
            let mediaFile = URL(filePath: path).standardizedFileURL
            let mediaPath = mediaFile.path(percentEncoded: false)
            do {
                guard FileManager.default.fileExists(atPath: mediaPath) else {
                    throw Failure(description: "file not found")
                }
                let output = SubtitleFile.url(for: mediaFile, format: options.format)
                if !options.force, FileManager.default.fileExists(atPath: output.path(percentEncoded: false)) {
                    throw Failure(description: "\(output.lastPathComponent) already exists (use --force to replace it)")
                }
                if let modelFailure {
                    throw modelFailure
                }
                if transcriber == nil {
                    let loaded = try await Transcriber.load { progress($0) }
                    progress("Model: \(loaded.model.model.displayName) (from \(loaded.model.owner.name))")
                    transcriber = loaded
                }
                let name = mediaFile.lastPathComponent
                let result = try await subtitleOne(
                    mediaFile,
                    output: output,
                    with: transcriber!,
                    speechDetector: speechDetector,
                    speakerDiarizer: options.speakers ? speakerDiarizer : nil,
                    options: options,
                    onPhase: { phase in progress("\(name): \(phase)") }
                )
                results.append(result)
                if !options.json, let subtitleFile = result.subtitleFile {
                    print(subtitleFile)
                }
            } catch {
                failed = true
                progress("\(mediaFile.lastPathComponent): \(error)")
                results.append(SubtitlingResult(mediaFile: mediaPath, error: "\(error)"))
                if error is Transcriber.Failure {
                    modelFailure = error
                }
            }
        }

        if options.json {
            do {
                print(try SubtitlingResult.encodeJSON(results))
            } catch {
                failed = true
                progress("Could not encode JSON output: \(error)")
            }
        }
        return failed ? ExitCode.failure : ExitCode.ok
    }

    /// Subtitles one Media File using an already-loaded `Transcriber` and `SpeechDetector`.
    /// Shared by the CLI, Watched Folder, MCP server, and GUI.
    static func subtitleOne(
        _ mediaFile: URL,
        output: URL,
        with transcriber: Transcriber,
        speechDetector: SpeechDetector,
        speakerDiarizer: SpeakerDiarizer? = nil,
        options: Command.Options,
        onPhase: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> SubtitlingResult {
        let started = Date()
        onPhase("reading audio")
        let temporary = FileManager.default.temporaryDirectory.appending(path: "Sottovoce", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let audio = try await AudioExtraction.run(mediaFile, into: temporary)
        defer { try? FileManager.default.removeItem(at: audio.url) }
        if audio.skipped > 0 {
            onPhase("\(String(format: "%.1f", audio.skipped)) s of unreadable audio replaced with silence")
        }
        onPhase("transcribing \(duration(audio.duration))")
        var transcript = try await transcriber.transcribe(audio.url, speechDetector: speechDetector)
        if options.speakers, let speakerDiarizer, !transcript.words.isEmpty {
            let turns = try await speakerDiarizer.turns(inFile: audio.url, onPhase: onPhase)
            transcript = assigningSpeakers(to: transcript, turns: turns)
        }
        let vocabulary = Vocabulary.load()
        transcript = vocabulary.applying(to: transcript)

        let cues: [Cue]
        switch options.style {
        case .classic:
            cues = options.classicStyle.cues(transcript)
        case .short:
            cues = ShortStyle(words: options.words, frameDuration: await frameDuration(of: mediaFile)).cues(transcript)
        }
        let content = SubtitleFile.render(cues, format: options.format)
        try Data(content.utf8).write(to: output, options: .atomic)
        let language = detectLanguage(of: transcript)
        onPhase("\(cues.count) cues, \(transcript.words.count) words in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        return SubtitlingResult(
            mediaFile: mediaFile.path(percentEncoded: false),
            subtitleFile: output.path(percentEncoded: false),
            format: options.format,
            style: options.style,
            language: language,
            duration: (audio.duration * 1000).rounded() / 1000,
            cues: cues.count
        )
    }

    /// Parakeet does not report the language it heard: read it from the Transcript text.
    private static func detectLanguage(of transcript: Transcript) -> String? {
        let text = transcript.words.map(\.text).joined(separator: " ")
        guard !text.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    /// The duration of one frame of the Media File's video track; nil for audio only.
    private static func frameDuration(of mediaFile: URL) async -> TimeInterval? {
        if let track = try? await AVURLAsset(url: mediaFile).loadTracks(withMediaType: .video).first {
            if let minimum = try? await track.load(.minFrameDuration), minimum.isNumeric, minimum.seconds > 0 {
                return minimum.seconds
            }
            if let rate = try? await track.load(.nominalFrameRate), rate > 0 {
                return 1 / Double(rate)
            }
        }
        return AudioExtraction.frameDurationWithFFprobe(of: mediaFile)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    static func progress(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
