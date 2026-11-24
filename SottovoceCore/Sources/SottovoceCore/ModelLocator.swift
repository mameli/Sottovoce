import Foundation

/// Where a Parakeet or Silero VAD model is on this Mac (ADR 0005): in Sottovoce's own folder or
/// borrowed from a Sister App, preferring Ultra to v3 wherever it is, and only when its owner
/// marked it as fully downloaded.
public struct ModelLocator: Sendable {
    public struct Owner: Equatable, Sendable {
        public let name: String
        /// The folder holding one subfolder per model, named after the model.
        public let modelsFolder: URL
        /// The file the owner writes next to a model once it is fully downloaded.
        public let marker: String
    }

    public enum Model: String, CaseIterable, Sendable {
        case ultra = "parakeet-ultra"
        case v3 = "parakeet-tdt-0.6b-v3"

        public var displayName: String {
            switch self {
            case .ultra: "Parakeet Ultra"
            case .v3: "Parakeet v3"
            }
        }
    }

    public struct Found: Equatable, Sendable {
        public let model: Model
        public let folder: URL
        public let owner: Owner

        public init(model: Model, folder: URL, owner: Owner) {
            self.model = model
            self.folder = folder
            self.owner = owner
        }
    }

    /// Relative path inside an owner's `modelsFolder` where FluidAudio stores Silero VAD.
    public static let sileroRelativeFolder = "Models/silero-vad"
    /// Compiled CoreML file FluidAudio needs to load Silero VAD without downloading.
    public static let sileroRequiredFile = "Models/silero-vad/silero-vad-unified-256ms-v6.2.1.mlmodelc/coremldata.bin"

    public let owners: [Owner]

    public init(owners: [Owner]) {
        self.owners = owners
    }

    /// Sottovoce's own owner entry (always the first owner).
    public var own: Owner { owners[0] }

    /// Sottovoce's own folder for a Parakeet model.
    public func ownFolder(for model: Model) -> URL {
        own.modelsFolder.appending(path: model.rawValue, directoryHint: .isDirectory)
    }

    /// Marker file written inside Sottovoce's own folder once a download completes.
    public func ownMarker(for model: Model) -> URL {
        ownFolder(for: model).appending(path: own.marker)
    }

    /// Marker file written inside Sottovoce's Silero VAD folder once a download completes.
    public var ownSileroMarker: URL {
        own.modelsFolder.appending(path: Self.sileroRelativeFolder, directoryHint: .isDirectory)
            .appending(path: own.marker)
    }

    /// Sottovoce, then Takku, then Dimmela, under `applicationSupport`.
    public static func standard(applicationSupport: URL) -> ModelLocator {
        func owner(_ name: String, _ marker: String) -> Owner {
            Owner(
                name: name,
                modelsFolder: applicationSupport.appending(path: "\(name)/Models/fluidaudio", directoryHint: .isDirectory),
                marker: marker
            )
        }
        return ModelLocator(owners: [
            owner("Sottovoce", ".sottovoce-downloaded"),
            owner("Takku", ".takku-downloaded"),
            owner("Dimmela", ".dimmela-downloaded"),
        ])
    }

    /// Every usable Parakeet model, best first: Ultra in any owner's folder, then v3.
    public func candidates(fileExists: (URL) -> Bool) -> [Found] {
        Model.allCases.flatMap { model in
            owners.compactMap { owner in
                let folder = owner.modelsFolder.appending(path: model.rawValue, directoryHint: .isDirectory)
                return fileExists(folder.appending(path: owner.marker)) ? Found(model: model, folder: folder, owner: owner) : nil
            }
        }
    }

    /// Every owner that already has a usable Silero VAD model on disk, own folder first.
    /// Sottovoce's own folder requires its marker; Sister Apps (which do not write a marker for
    /// Silero) are checked for the compiled CoreML model file so we never trigger a download into
    /// their folders.
    public func sileroCandidates(fileExists: (URL) -> Bool) -> [Owner] {
        owners.enumerated().compactMap { index, owner in
            let modelFile = owner.modelsFolder.appending(path: Self.sileroRequiredFile)
            guard fileExists(modelFile) else { return nil }
            if index == 0 {
                let marker = owner.modelsFolder
                    .appending(path: Self.sileroRelativeFolder, directoryHint: .isDirectory)
                    .appending(path: owner.marker)
                guard fileExists(marker) else { return nil }
            }
            return owner
        }
    }
}
