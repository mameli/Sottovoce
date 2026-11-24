import Foundation
import SottovoceCore

/// `sottovoce watch <folder> [options]`: keeps running and subtitles every Media File that lands
/// in `<folder>`, waiting until a file's size settles before reading it.
enum WatchedFolder {
    private struct FileStamp: Equatable {
        let size: Int64
        let modified: Date
    }

    private static let ignoredExtensions: Set<String> = ["srt", "vtt", "tmp", "part", "download", "crdownload"]
    private static let pollInterval: Duration = .seconds(2)

    static func run(_ folderPath: String, options: Command.Options) async -> Int32 {
        let folder = URL(filePath: folderPath).resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            Subtitling.progress("watch: not a folder: \(folder.path(percentEncoded: false))")
            return ExitCode.failure
        }

        Subtitling.progress("Watching \(folder.path(percentEncoded: false))")
        var transcriber: Transcriber?
        let speechDetector = SpeechDetector { Subtitling.progress($0) }
        let speakerDiarizer = SpeakerDiarizer()

        // Files seen on the previous poll, so a file still being written/copied settles first.
        var pendingStability: [String: FileStamp] = [:]
        // Files already handled (succeeded or failed) at a given stamp.
        var handled: [String: FileStamp] = [:]

        while !Task.isCancelled {
            let entries = listCandidateFiles(in: folder)
            var currentPaths = Set<String>()
            for (url, stamp) in entries {
                let path = url.path(percentEncoded: false)
                currentPaths.insert(path)
                if handled[path] == stamp { continue }

                let output = SubtitleFile.url(for: url, format: options.format)
                if !options.force, FileManager.default.fileExists(atPath: output.path(percentEncoded: false)) {
                    handled[path] = stamp
                    continue
                }

                // Wait for the file size & mtime to match across two consecutive polls.
                if pendingStability[path] != stamp {
                    pendingStability[path] = stamp
                    continue
                }
                pendingStability[path] = nil

                do {
                    if transcriber == nil {
                        let loaded = try await Transcriber.load { Subtitling.progress($0) }
                        Subtitling.progress("Model: \(loaded.model.model.displayName) (from \(loaded.model.owner.name))")
                        transcriber = loaded
                    }
                    let name = url.lastPathComponent
                    let result = try await Subtitling.subtitleOne(
                        url,
                        output: output,
                        with: transcriber!,
                        speechDetector: speechDetector,
                        speakerDiarizer: options.speakers ? speakerDiarizer : nil,
                        options: options,
                        onPhase: { phase in Subtitling.progress("\(name): \(phase)") }
                    )
                    handled[path] = stamp
                    if options.json {
                        if let json = try? SubtitlingResult.encodeJSON([result]) {
                            FileHandle.standardOutput.write(Data((json + "\n").utf8))
                        }
                    } else if let subtitleFile = result.subtitleFile {
                        FileHandle.standardOutput.write(Data((subtitleFile + "\n").utf8))
                    }
                } catch {
                    handled[path] = stamp
                    Subtitling.progress("\(url.lastPathComponent): \(error)")
                }
            }
            pendingStability = pendingStability.filter { currentPaths.contains($0.key) }
            try? await Task.sleep(for: pollInterval)
        }
        return ExitCode.ok
    }

    private static func listCandidateFiles(in folder: URL) -> [(URL, FileStamp)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        } catch {
            Subtitling.progress("watch: could not read folder: \(error.localizedDescription)")
            return []
        }
        return urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { url in
            let ext = url.pathExtension.lowercased()
            guard !ext.isEmpty, !ignoredExtensions.contains(ext) else { return nil }
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true,
                  let size = values.fileSize, size > 0,
                  let modified = values.contentModificationDate
            else { return nil }
            return (url, FileStamp(size: Int64(size), modified: modified))
        }
    }
}
