import AVFoundation
@preconcurrency import FluidAudio
import Foundation
import SottovoceCore

/// Tells voices apart locally with NVIDIA's Nemotron 3 Diarization through FluidAudio (adapted
/// from Takku's `SpeakerDiarizer`). Borrows the model from Sister Apps when present (ADR 0005),
/// otherwise downloads it into Sottovoce's own models folder with `.sottovoce-downloaded`.
actor SpeakerDiarizer {
    private var diarizer: Nemotron3Diarizer?
    private static let blockSeconds = 30.0

    /// The turns of each voice in a 16 kHz mono WAV file, with times from its start.
    func turns(inFile url: URL, onPhase: @escaping @Sendable (String) -> Void = { _ in }) async throws -> [SpeakerTurn] {
        let diarizer = try await loaded(onPhase: onPhase)
        onPhase("identifying speakers")
        diarizer.reset()

        let file = try AVAudioFile(forReading: url)
        let blockFrames = AVAudioFrameCount(Self.blockSeconds * file.processingFormat.sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: blockFrames) else {
            return []
        }

        var probabilities: [Float] = []
        var frameCount = 0
        func collect(_ chunks: [Nemotron3ChunkResult]) {
            for chunk in chunks {
                probabilities.append(contentsOf: chunk.probabilities)
                frameCount += chunk.frameCount
            }
        }

        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: blockFrames)
            guard buffer.frameLength > 0, let channel = buffer.floatChannelData?[0] else { break }
            diarizer.appendAudio(Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
            collect(try diarizer.processBufferedAudio())
        }
        collect(try diarizer.finishStream())

        return Nemotron3Diarizer.segments(probabilities: probabilities, frameCount: frameCount).map {
            SpeakerTurn(voice: "S\($0.speakerIndex)", start: TimeInterval($0.startSeconds), end: TimeInterval($0.endSeconds))
        }
    }

    private func loaded(onPhase: @Sendable (String) -> Void) async throws -> Nemotron3Diarizer {
        if let diarizer { return diarizer }
        onPhase("loading speaker model")
        let locator = ModelLocator.standard(applicationSupport: .applicationSupportDirectory)
        let candidates = locator.nemotronCandidates {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }
        for owner in candidates {
            do {
                let models = try await Nemotron3Models.loadFromHuggingFace(config: .offline, cacheDirectory: owner.modelsFolder)
                let loaded = Nemotron3Diarizer(config: .offline, models: models)
                self.diarizer = loaded
                return loaded
            } catch {
                continue
            }
        }

        // Download into Sottovoce's own folder; never write into a Sister App's folder.
        let ownFolder = locator.own.modelsFolder
        let nemotronFolder = ownFolder.appending(path: ModelLocator.nemotronRelativeFolder, directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: nemotronFolder.path(percentEncoded: false)),
           !FileManager.default.fileExists(atPath: locator.ownNemotronMarker.path(percentEncoded: false)) {
            try? FileManager.default.removeItem(at: nemotronFolder)
        }
        onPhase("downloading speaker model")
        try FileManager.default.createDirectory(at: ownFolder, withIntermediateDirectories: true)
        let models = try await Nemotron3Models.loadFromHuggingFace(config: .offline, cacheDirectory: ownFolder)
        try Data().write(to: locator.ownNemotronMarker)
        let loaded = Nemotron3Diarizer(config: .offline, models: models)
        self.diarizer = loaded
        return loaded
    }
}
