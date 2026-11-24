import Foundation

/// What the `sottovoce` command was asked to do, read from its arguments. Parsing only: the app
/// runs it, since transcription needs frameworks this package does not depend on.
public enum Command: Equatable, Sendable {
    case help
    case version
    /// Subtitle each Media File, one at a time.
    case subtitle(mediaFiles: [String], options: Options)

    public struct Options: Equatable, Sendable {
        /// Replace an existing Subtitle File instead of failing.
        public var force = false

        public init(force: Bool = false) {
            self.force = force
        }
    }

    /// The commands that are not a Media File. Run as `Sottovoce` (inside the bundle), only these,
    /// or a path to an existing file, make the executable act as the CLI instead of the app.
    public static let names: Set<String> = ["help", "version", "--help", "-h", "--version"]

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case unknownOption(String)

        public var description: String {
            switch self {
            case .unknownOption(let option): "Unknown option: \(option)"
            }
        }
    }

    public static func parse(_ arguments: [String]) throws(ParseError) -> Command {
        guard let first = arguments.first else { return .help }
        switch first {
        case "help", "--help", "-h": return .help
        case "version", "--version": return .version
        default: break
        }
        var options = Options()
        var mediaFiles: [String] = []
        for argument in arguments {
            switch argument {
            case "--force", "-f": options.force = true
            case let option where option.hasPrefix("-"): throw .unknownOption(option)
            default: mediaFiles.append(argument)
            }
        }
        guard !mediaFiles.isEmpty else { return .help }
        return .subtitle(mediaFiles: mediaFiles, options: options)
    }

    public static let usage = """
        Usage: sottovoce <media-file>...

        Writes a subtitle file next to each video or audio file, with the same name
        (interview.mov -> interview.srt), and prints its path.

        Options:
          -f, --force    Replace a subtitle file that already exists

        Commands:
          help       Show this help
          version    Show the version
        """
}

/// Exit codes of the CLI (sysexits.h where one fits).
public enum ExitCode {
    public static let ok: Int32 = 0
    public static let failure: Int32 = 1
    public static let usage: Int32 = 64
}
