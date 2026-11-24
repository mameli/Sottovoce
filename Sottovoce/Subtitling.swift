import Foundation
import SottovoceCore

/// `sottovoce <media-file>...`: subtitles each Media File in turn, the Queue of the CLI. Progress
/// goes to stderr; stdout gets only the path of each Subtitle File written, so an agent can read it.
enum Subtitling {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    static func run(_ mediaFiles: [String], options: Command.Options) async -> Int32 {
        var transcriber: Transcriber?
        var failed = false
        for path in mediaFiles {
            let mediaFile = URL(filePath: path).standardizedFileURL
            do {
                if transcriber == nil {
                    let loaded = try await Transcriber.load()
                    progress("Model: \(loaded.model.model.displayName) (from \(loaded.model.owner.name))")
                    transcriber = loaded
                }
                let written = try await subtitle(mediaFile, with: transcriber!, options: options)
                print(written.path(percentEncoded: false))
            } catch {
                failed = true
                progress("\(mediaFile.lastPathComponent): \(error)")
                if error is Transcriber.Failure { break }
            }
        }
        return failed ? ExitCode.failure : ExitCode.ok
    }

    private static func subtitle(_ mediaFile: URL, with transcriber: Transcriber, options: Command.Options) async throws -> URL {
        let name = mediaFile.lastPathComponent
        guard FileManager.default.fileExists(atPath: mediaFile.path(percentEncoded: false)) else {
            throw Failure(description: "file not found")
        }
        let output = SubtitleFile.url(for: mediaFile)
        if !options.force, FileManager.default.fileExists(atPath: output.path(percentEncoded: false)) {
            throw Failure(description: "\(output.lastPathComponent) already exists (use --force to replace it)")
        }
        let started = Date()
        progress("\(name): reading audio")
        let temporary = FileManager.default.temporaryDirectory.appending(path: "Sottovoce", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let audio = try await AudioExtraction.run(mediaFile, into: temporary)
        defer { try? FileManager.default.removeItem(at: audio.url) }
        if audio.skipped > 0 {
            progress("\(name): \(String(format: "%.1f", audio.skipped)) s of unreadable audio replaced with silence")
        }
        progress("\(name): transcribing \(duration(audio.duration))")
        let transcript = try await transcriber.transcribe(audio.url)
        let cues = transcript.sentenceCues()
        try Data(SubtitleFile.srt(cues).utf8).write(to: output, options: .atomic)
        progress("\(name): \(cues.count) cues, \(transcript.words.count) words in \(String(format: "%.1f", Date().timeIntervalSince(started))) s")
        return output
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }

    static func progress(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
