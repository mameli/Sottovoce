import Foundation

/// Where a Parakeet model is on this Mac (ADR 0005): in Sottovoce's own folder or borrowed from a
/// Sister App, preferring Ultra to v3 wherever it is, and only when its owner marked it as fully
/// downloaded.
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
    }

    public let owners: [Owner]

    public init(owners: [Owner]) {
        self.owners = owners
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

    /// Every usable model, best first: Ultra in any owner's folder, then v3.
    public func candidates(fileExists: (URL) -> Bool) -> [Found] {
        Model.allCases.flatMap { model in
            owners.compactMap { owner in
                let folder = owner.modelsFolder.appending(path: model.rawValue, directoryHint: .isDirectory)
                return fileExists(folder.appending(path: owner.marker)) ? Found(model: model, folder: folder, owner: owner) : nil
            }
        }
    }
}
