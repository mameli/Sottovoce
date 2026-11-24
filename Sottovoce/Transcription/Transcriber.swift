@preconcurrency import FluidAudio
import Foundation
import SottovoceCore

/// Parakeet through FluidAudio (ADR 0002), with the model found by `ModelLocator` (ADR 0005).
/// Loaded once, then used for every Media File of the Queue.
actor Transcriber {
    enum Failure: Error, CustomStringConvertible {
        case noModel

        var description: String {
            switch self {
            case .noModel:
                "No Parakeet model on this Mac. Downloading it is not implemented yet: open Takku or Dimmela once to download one."
            }
        }
    }

    private let asr: AsrManager
    let model: ModelLocator.Found

    private init(asr: AsrManager, model: ModelLocator.Found) {
        self.asr = asr
        self.model = model
    }

    /// Loads the best model found, falling back to the next one when a borrowed model fails to load.
    static func load() async throws -> Transcriber {
        // FluidAudio writes its own progress to stderr, which belongs to Sottovoce's messages.
        AppLogger.mirrorsToConsole = false
        AppLogger.minimumLevel = .warning
        let locator = ModelLocator.standard(applicationSupport: .applicationSupportDirectory)
        let candidates = locator.candidates { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
        var lastError: Error = Failure.noModel
        for candidate in candidates {
            do {
                let version: AsrModelVersion = candidate.model == .ultra ? .ultra : .v3
                let models = try await AsrModels.load(from: candidate.folder, version: version)
                return Transcriber(asr: AsrManager(config: .default, models: models), model: candidate)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// The Transcript of a 16 kHz mono audio file.
    func transcribe(_ audio: URL) async throws -> Transcript {
        var state = TdtDecoderState.make()
        let result = try await asr.transcribe(audio, decoderState: &state)
        let tokens = (result.tokenTimings ?? []).map {
            TimedToken(text: $0.token, start: $0.startTime, end: $0.endTime)
        }
        return Transcript(tokens: tokens)
    }
}
