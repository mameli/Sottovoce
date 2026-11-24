import AVFoundation

/// The audio track of a Media File as 16 kHz mono, the format Parakeet expects, written to a
/// temporary WAV file so that a two-hour film never sits in memory.
///
/// Read with AVAssetReader, which sees the whole track: AVAudioFile, which Takku uses, reported
/// 175 s of a 19-minute MP4 merged by yt-dlp and stopped there. When AVAssetReader fails, Takku's
/// AVAudioFile reading takes over (ADR 0003): macOS's decoder can fail in the middle of a file other
/// players read, so a failed stretch is read again one AAC packet at a time and only what stays
/// unreadable is replaced with silence.
enum AudioExtraction {
    enum Failure: Error, CustomStringConvertible {
        case unreadable(String)
        case noAudio(String)
        case unsupportedFormat(String)
        case ffmpegMissing

        var description: String {
            switch self {
            case .unreadable: "not a video or audio file macOS can read"
            case .noAudio: "no audio track"
            case .unsupportedFormat(let format): "unsupported audio format: \(format)"
            case .ffmpegMissing: "not a video or audio file macOS can read; install ffmpeg with `brew install ffmpeg`"
            }
        }
    }

    struct Extracted {
        let url: URL
        let duration: TimeInterval
        /// Seconds of unreadable audio replaced with silence.
        let skipped: TimeInterval
    }

    static let sampleRate: Double = 16_000
    /// Frames read at a time: about a second of audio.
    private static let framesPerRead: AVAudioFrameCount = 48_000
    /// Frames read at a time after a read error: one AAC packet, the smallest stretch skipped.
    private static let framesPerCarefulRead: AVAudioFrameCount = 1024

    static func run(_ mediaFile: URL, into directory: URL) async throws -> Extracted {
        do {
            return try await readWithAssetReader(mediaFile, into: directory)
        } catch Failure.noAudio(let name) {
            throw Failure.noAudio(name)
        } catch {
            do {
                return try readWithAudioFile(mediaFile, into: directory)
            } catch Failure.noAudio(let name) {
                throw Failure.noAudio(name)
            } catch {
                return try await readWithFFmpeg(mediaFile, into: directory)
            }
        }
    }

    /// Locates Homebrew's `ffmpeg` (or `ffprobe`) without bundling it (ADR 0009).
    static func findTool(_ name: String) -> URL? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(filePath: path)
        }
        if let envPath = ProcessInfo.processInfo.environment["PATH"] {
            for dir in envPath.split(separator: ":") {
                let candidate = "\(dir)/\(name)"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return URL(filePath: candidate)
                }
            }
        }
        return nil
    }

    /// Fallback for containers AVFoundation cannot open (MKV, WebM, etc.) via Homebrew `ffmpeg`.
    private static func readWithFFmpeg(_ mediaFile: URL, into directory: URL) async throws -> Extracted {
        let name = mediaFile.lastPathComponent
        guard let ffmpeg = findTool("ffmpeg") else {
            throw Failure.ffmpegMissing
        }
        let url = directory.appending(path: "\(UUID().uuidString).wav")
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = [
            "-nostdin",
            "-v", "error",
            "-y",
            "-i", mediaFile.path(percentEncoded: false),
            "-vn",
            "-ac", "1",
            "-ar", String(Int(sampleRate)),
            "-c:a", "pcm_s16le",
            url.path(percentEncoded: false),
        ]
        let stderr = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let errText = String(decoding: errData, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: url)
            if errText.localizedCaseInsensitiveContains("does not contain any stream")
                || errText.localizedCaseInsensitiveContains("matches no streams") {
                throw Failure.noAudio(name)
            }
            throw Failure.unreadable(name)
        }
        do {
            let wav = try AVAudioFile(forReading: url)
            guard wav.length > 0 else {
                try? FileManager.default.removeItem(at: url)
                throw Failure.noAudio(name)
            }
            return Extracted(url: url, duration: Double(wav.length) / wav.processingFormat.sampleRate, skipped: 0)
        } catch let failure as Failure {
            throw failure
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw Failure.unreadable(name)
        }
    }

    /// Reads the video track's frame duration via `ffprobe` when AVFoundation cannot open the file.
    static func frameDurationWithFFprobe(of mediaFile: URL) -> TimeInterval? {
        guard let ffprobe = findTool("ffprobe") else { return nil }
        let process = Process()
        process.executableURL = ffprobe
        process.arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=avg_frame_rate,r_frame_rate",
            "-of", "default=noprint_wrappers=1:nokey=1",
            mediaFile.path(percentEncoded: false),
        ]
        let stdout = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(decoding: outData, as: UTF8.self)
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "/")
            if parts.count == 2, let num = Double(parts[0]), let den = Double(parts[1]), num > 0, den > 0 {
                return den / num
            }
            if parts.count == 1, let fps = Double(parts[0]), fps > 0 {
                return 1 / fps
            }
        }
        return nil
    }

    private static var wavSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
    }

    private static func readWithAssetReader(_ mediaFile: URL, into directory: URL) async throws -> Extracted {
        let name = mediaFile.lastPathComponent
        let asset = AVURLAsset(url: mediaFile)
        let tracks: [AVAssetTrack]
        do {
            tracks = try await asset.loadTracks(withMediaType: .audio)
        } catch {
            throw Failure.unreadable(name)
        }
        guard let track = tracks.first else { throw Failure.noAudio(name) }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading(),
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
        else { throw reader.error ?? Failure.unreadable(name) }

        let url = directory.appending(path: "\(UUID().uuidString).wav")
        var frames: AVAudioFramePosition = 0
        do {
            let writer = try AVAudioFile(forWriting: url, settings: wavSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
            while let sample = output.copyNextSampleBuffer() {
                guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
                let bytes = CMBlockBufferGetDataLength(block)
                let count = bytes / MemoryLayout<Float>.size
                guard count > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { continue }
                let status = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size, destination: buffer.floatChannelData![0])
                guard status == kCMBlockBufferNoErr else { throw Failure.unreadable(name) }
                buffer.frameLength = AVAudioFrameCount(count)
                try writer.write(from: buffer)
                frames += AVAudioFramePosition(count)
            }
            guard reader.status == .completed, frames > 0 else { throw reader.error ?? Failure.noAudio(name) }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        return Extracted(url: url, duration: Double(frames) / sampleRate, skipped: 0)
    }

    private static func readWithAudioFile(_ mediaFile: URL, into directory: URL) throws -> Extracted {
        let name = mediaFile.lastPathComponent
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: mediaFile)
        } catch {
            throw Failure.unreadable(name)
        }
        guard file.length > 0 else { throw Failure.noAudio(name) }
        let input = file.processingFormat
        guard input.sampleRate.isFinite, input.sampleRate > 0,
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: output),
              let readBuffer = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: framesPerRead)
        else { throw Failure.unsupportedFormat(input.description) }

        let url = directory.appending(path: "\(UUID().uuidString).wav")
        let writer = try AVAudioFile(forWriting: url, settings: wavSettings, commonFormat: .pcmFormatFloat32, interleaved: false)

        var carefulUntil: AVAudioFramePosition = 0
        var skippedFrames: AVAudioFramePosition = 0
        while file.framePosition < file.length {
            let position = file.framePosition
            let isCareful = position < carefulUntil
            do {
                try file.read(into: readBuffer, frameCount: isCareful ? framesPerCarefulRead : framesPerRead)
            } catch {
                if isCareful {
                    let end = min(position + AVAudioFramePosition(framesPerCarefulRead), file.length)
                    try writeSilence(frames: end - position, inputRate: input.sampleRate, to: writer, format: output)
                    skippedFrames += end - position
                    file.framePosition = end
                } else {
                    carefulUntil = position + AVAudioFramePosition(framesPerRead)
                    file.framePosition = position
                }
                continue
            }
            guard readBuffer.frameLength > 0 else { break }
            try convert(readBuffer, with: converter, to: writer, format: output)
        }
        if skippedFrames == file.length { throw Failure.unreadable(name) }
        return Extracted(
            url: url,
            duration: Double(file.length) / input.sampleRate,
            skipped: Double(skippedFrames) / input.sampleRate
        )
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter, to writer: AVAudioFile, format: AVAudioFormat) throws {
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate).rounded(.up)) + 32
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if let error { throw error }
        if converted.frameLength > 0 { try writer.write(from: converted) }
    }

    private static func writeSilence(frames: AVAudioFramePosition, inputRate: Double, to writer: AVAudioFile, format: AVAudioFormat) throws {
        let count = AVAudioFrameCount((Double(frames) * format.sampleRate / inputRate).rounded())
        guard count > 0, let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count) else { return }
        silence.frameLength = count
        try writer.write(from: silence)
    }
}
