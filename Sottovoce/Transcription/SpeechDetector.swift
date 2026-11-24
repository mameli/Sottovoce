@preconcurrency import FluidAudio
import Foundation
import SottovoceCore

/// Silero voice activity detection through FluidAudio (adapted from Takku's `SpeechDetector`):
/// returns the speech probability of every 256 ms of 16 kHz mono audio so music, silence and noise
/// are skipped before transcription. Borrows Silero from the Sister Apps when already present
/// (ADR 0005), otherwise downloads it into Sottovoce's own models folder.
actor SpeechDetector {
    private var loading: Task<VadManager?, Never>?
    private let onProgress: @Sendable (String) -> Void

    init(onProgress: @escaping @Sendable (String) -> Void = { _ in }) {
        self.onProgress = onProgress
    }

    /// One probability per 256 ms of 16 kHz mono `samples`, or `nil` when Silero is unavailable.
    func speechProbabilities(_ samples: [Float]) async -> [Float]? {
        guard !samples.isEmpty, let manager = await loaded() else { return nil }
        do {
            return try await manager.process(samples).map(\.probability)
        } catch {
            onProgress("Speech detection failed, transcribing full audio: \(error)")
            return nil
        }
    }

    private func loaded() async -> VadManager? {
        if let loading { return await loading.value }
        let onProgress = self.onProgress
        let loading = Task<VadManager?, Never> {
            let locator = ModelLocator.standard(applicationSupport: .applicationSupportDirectory)
            let config = VadConfig(defaultThreshold: SpeechDetection.threshold)
            let candidates = locator.sileroCandidates {
                FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
            }
            for owner in candidates {
                do {
                    return try await VadManager(config: config, modelDirectory: owner.modelsFolder)
                } catch {
                    continue
                }
            }
            // Download into Sottovoce's own folder; never write into a Sister App's folder.
            let ownFolder = locator.own.modelsFolder
            let sileroFolder = ownFolder.appending(path: ModelLocator.sileroRelativeFolder, directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: sileroFolder.path(percentEncoded: false)),
               !FileManager.default.fileExists(atPath: locator.ownSileroMarker.path(percentEncoded: false)) {
                try? FileManager.default.removeItem(at: sileroFolder)
            }
            onProgress("Downloading Silero VAD...")
            do {
                try FileManager.default.createDirectory(at: ownFolder, withIntermediateDirectories: true)
                let manager = try await VadManager(config: config, modelDirectory: ownFolder)
                try Data().write(to: locator.ownSileroMarker)
                return manager
            } catch {
                onProgress("Silero VAD unavailable, transcribing full audio: \(error)")
                return nil
            }
        }
        self.loading = loading
        return await loading.value
    }
}
