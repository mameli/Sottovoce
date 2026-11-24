import Foundation
import SottovoceCore

/// Serial in-process Queue behind `sottovoce mcp`: accepts Media Files immediately and processes
/// them one at a time on a background worker, reusing the loaded `Transcriber` and `SpeechDetector`.
final class MCPSubtitlingService: SubtitlingService, @unchecked Sendable {
    private struct Request: Sendable {
        let mediaFile: URL
        let output: URL
        let options: Command.Options
    }

    private let lock = NSLock()
    private var order: [String] = []
    private var jobs: [String: SubtitleJobStatus] = [:]
    private let continuation: AsyncStream<Request>.Continuation

    init() {
        var captured: AsyncStream<Request>.Continuation!
        let stream = AsyncStream<Request> { captured = $0 }
        self.continuation = captured
        Task.detached { [weak self] in
            await self?.runWorker(stream)
        }
    }

    deinit {
        continuation.finish()
    }

    func enqueue(mediaFile: String, options: Command.Options) -> Result<SubtitleJobStatus, Error> {
        let url = URL(filePath: mediaFile).standardizedFileURL
        let mediaPath = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: mediaPath) else {
            return .failure(Subtitling.Failure(description: "file not found: \(mediaPath)"))
        }
        let output = SubtitleFile.url(for: url, format: options.format)
        let outputPath = output.path(percentEncoded: false)
        if !options.force, FileManager.default.fileExists(atPath: outputPath) {
            return .failure(Subtitling.Failure(description: "\(output.lastPathComponent) already exists (pass force: true to replace it)"))
        }

        let queued = SubtitleJobStatus(
            mediaFile: mediaPath,
            subtitleFile: outputPath,
            state: .queued,
            phase: "queued",
            format: options.format,
            style: options.style
        )
        lock.lock()
        if jobs[mediaPath] == nil {
            order.append(mediaPath)
        }
        jobs[mediaPath] = queued
        lock.unlock()

        continuation.yield(Request(mediaFile: url, output: output, options: options))
        return .success(queued)
    }

    func status(forPath path: String?) -> [SubtitleJobStatus] {
        lock.lock()
        defer { lock.unlock() }
        guard let path else {
            return order.compactMap { jobs[$0] }
        }
        let standardized = URL(filePath: path).standardizedFileURL.path(percentEncoded: false)
        if let direct = jobs[standardized] {
            return [direct]
        }
        if let bySubtitle = jobs.values.first(where: { $0.subtitleFile == standardized }) {
            return [bySubtitle]
        }
        return []
    }

    private func update(_ mediaPath: String, _ transform: (SubtitleJobStatus) -> SubtitleJobStatus) {
        lock.lock()
        if let current = jobs[mediaPath] {
            jobs[mediaPath] = transform(current)
        }
        lock.unlock()
    }

    private func runWorker(_ stream: AsyncStream<Request>) async {
        var transcriber: Transcriber?
        let speechDetector = SpeechDetector()
        let speakerDiarizer = SpeakerDiarizer()
        for await request in stream {
            let mediaPath = request.mediaFile.path(percentEncoded: false)
            let outputPath = request.output.path(percentEncoded: false)
            update(mediaPath) {
                SubtitleJobStatus(
                    mediaFile: $0.mediaFile,
                    subtitleFile: $0.subtitleFile,
                    state: .running,
                    phase: transcriber == nil ? "loading model" : "starting",
                    format: $0.format,
                    style: $0.style
                )
            }
            do {
                if transcriber == nil {
                    transcriber = try await Transcriber.load { [weak self] message in
                        self?.update(mediaPath) {
                            SubtitleJobStatus(
                                mediaFile: $0.mediaFile,
                                subtitleFile: $0.subtitleFile,
                                state: .running,
                                phase: message,
                                format: $0.format,
                                style: $0.style
                            )
                        }
                    }
                }
                let result = try await Subtitling.subtitleOne(
                    request.mediaFile,
                    output: request.output,
                    with: transcriber!,
                    speechDetector: speechDetector,
                    speakerDiarizer: request.options.speakers ? speakerDiarizer : nil,
                    options: request.options,
                    onPhase: { [weak self] phase in
                        self?.update(mediaPath) {
                            SubtitleJobStatus(
                                mediaFile: $0.mediaFile,
                                subtitleFile: $0.subtitleFile,
                                state: .running,
                                phase: phase,
                                format: $0.format,
                                style: $0.style
                            )
                        }
                    }
                )
                update(mediaPath) { _ in
                    SubtitleJobStatus(
                        mediaFile: mediaPath,
                        subtitleFile: outputPath,
                        state: .completed,
                        phase: "done",
                        format: request.options.format,
                        style: request.options.style,
                        language: result.language,
                        duration: result.duration,
                        cues: result.cues
                    )
                }
            } catch {
                update(mediaPath) {
                    SubtitleJobStatus(
                        mediaFile: $0.mediaFile,
                        subtitleFile: $0.subtitleFile,
                        state: .failed,
                        phase: nil,
                        format: $0.format,
                        style: $0.style,
                        error: "\(error)"
                    )
                }
            }
        }
    }
}
