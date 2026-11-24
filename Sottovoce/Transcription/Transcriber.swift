import AVFoundation
@preconcurrency import FluidAudio
import Foundation
import SottovoceCore

/// Parakeet through FluidAudio (ADR 0002), with the model found by `ModelLocator` (ADR 0005) or
/// downloaded into Sottovoce's own folder at first use. Loaded once, then used for every Media File
/// of the Queue.
actor Transcriber {
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    private let asr: AsrManager
    let model: ModelLocator.Found

    private init(asr: AsrManager, model: ModelLocator.Found) {
        self.asr = asr
        self.model = model
    }

    /// Loads the best model found, falling back to the next candidate when a borrowed model fails
    /// to load, and finally downloading Parakeet Ultra into Sottovoce's own folder.
    static func load(onProgress: @escaping @Sendable (String) -> Void = { _ in }) async throws -> Transcriber {
        // FluidAudio writes its own logs to stderr, which belongs to Sottovoce's messages.
        AppLogger.mirrorsToConsole = false
        AppLogger.minimumLevel = .warning

        let locator = ModelLocator.standard(applicationSupport: .applicationSupportDirectory)
        let candidates = locator.candidates { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
        for candidate in candidates {
            do {
                let version: AsrModelVersion = candidate.model == .ultra ? .ultra : .v3
                let models = try await AsrModels.load(from: candidate.folder, version: version)
                return Transcriber(asr: AsrManager(config: .default, models: models), model: candidate)
            } catch {
                onProgress("Could not load \(candidate.model.displayName) from \(candidate.owner.name), trying fallback")
            }
        }

        // No usable model found: download Parakeet Ultra into Sottovoce's own folder.
        let ownFolder = locator.ownFolder(for: .ultra)
        let marker = locator.ownMarker(for: .ultra)
        let interrupted = FileManager.default.fileExists(atPath: ownFolder.path(percentEncoded: false))
            && !FileManager.default.fileExists(atPath: marker.path(percentEncoded: false))
        do {
            try FileManager.default.createDirectory(
                at: ownFolder.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let reporter = ProgressReporter(label: "Downloading \(ModelLocator.Model.ultra.displayName)", emit: onProgress)
            reporter.report(0)
            let folder = try await AsrModels.download(to: ownFolder, force: interrupted, version: .ultra) { progress in
                reporter.report(progress.fractionCompleted)
            }
            reporter.finish()
            try Data().write(to: folder.appending(path: locator.own.marker))
            let models = try await AsrModels.load(from: folder, version: .ultra)
            let found = ModelLocator.Found(model: .ultra, folder: folder, owner: locator.own)
            return Transcriber(asr: AsrManager(config: .default, models: models), model: found)
        } catch {
            throw Failure(description: "could not download \(ModelLocator.Model.ultra.displayName): \(error.localizedDescription)")
        }
    }

    /// The Transcript of a 16 kHz mono WAV file. Runs Silero VAD first and transcribes only
    /// stretches with speech, shifting word times back to whole-Media-File time.
    func transcribe(_ audio: URL, speechDetector: SpeechDetector) async throws -> Transcript {
        let samples = try Self.loadSamples(audio)
        guard !samples.isEmpty else { return Transcript(words: []) }

        if let probabilities = await speechDetector.speechProbabilities(samples) {
            let ranges = SpeechDetection.speechRanges(probabilities: probabilities, totalSamples: samples.count)
            guard !ranges.isEmpty else { return Transcript(words: []) }
            let minimumSamples = ASRConstants.minimumRequiredSamples(forSampleRate: Int(SpeechDetection.sampleRate))
            var words: [Word] = []
            for range in ranges {
                var chunk = Array(samples[range.samples])
                if chunk.count < minimumSamples {
                    chunk.append(contentsOf: repeatElement(0, count: minimumSamples - chunk.count))
                }
                var state = TdtDecoderState.make()
                let result = try await asr.transcribe(chunk, decoderState: &state)
                let rawTokens = (result.tokenTimings ?? []).map {
                    TimedToken(text: $0.token, start: $0.startTime, end: $0.endTime)
                }
                let offset = Double(range.samples.lowerBound) / SpeechDetection.sampleRate
                let maxEnd = Double(range.samples.upperBound) / SpeechDetection.sampleRate
                let shifted = SpeechDetection.offsetTokens(rawTokens, by: offset, clampedTo: maxEnd)
                let rangeWords = Transcript(tokens: shifted).words
                if SpeechDetection.isLikelyHallucination(rangeWords, speechDuration: range.speechDuration) {
                    continue
                }
                words.append(contentsOf: rangeWords)
            }
            return Transcript(words: words)
        }

        // Fallback if Silero VAD could not load: transcribe the whole file directly.
        var state = TdtDecoderState.make()
        let result = try await asr.transcribe(audio, decoderState: &state)
        let tokens = (result.tokenTimings ?? []).map {
            TimedToken(text: $0.token, start: $0.startTime, end: $0.endTime)
        }
        return Transcript(tokens: tokens)
    }

    /// Reads 16 kHz mono Float32 samples in 10-second blocks (adapted from Takku).
    private static func loadSamples(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let blockFrames = AVAudioFrameCount(10 * SpeechDetection.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: blockFrames) else {
            return []
        }
        var samples: [Float] = []
        samples.reserveCapacity(Int(file.length))
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: blockFrames)
            guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        }
        return samples
    }
}

/// Emits monotonic download progress steps without flooding stderr.
private final class ProgressReporter: @unchecked Sendable {
    private let lock = NSLock()
    private let label: String
    private let emit: @Sendable (String) -> Void
    private var lastReported = -1

    init(label: String, emit: @escaping @Sendable (String) -> Void) {
        self.label = label
        self.emit = emit
    }

    func report(_ fraction: Double) {
        let percent = min(100, max(0, Int((fraction * 100).rounded(.down))))
        lock.lock()
        let shouldEmit = lastReported < 0 || percent == 100 || percent >= lastReported + 5
        if shouldEmit && percent > lastReported {
            lastReported = percent
            lock.unlock()
            emit("\(label): \(percent)%")
        } else {
            lock.unlock()
        }
    }

    func finish() {
        report(1.0)
    }
}
