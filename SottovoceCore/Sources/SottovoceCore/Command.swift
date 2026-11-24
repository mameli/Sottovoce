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
        public var style: Style = .classic
        /// Words per Cue in the Short Style.
        public var words = 1

        public init(force: Bool = false, style: Style = .classic, words: Int = 1) {
            self.force = force
            self.style = style
            self.words = words
        }
    }

    /// The commands that are not a Media File. Run as `Sottovoce` (inside the bundle), only these,
    /// or a path to an existing file, make the executable act as the CLI instead of the app.
    public static let names: Set<String> = ["help", "version", "--help", "-h", "--version"]

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case unknownOption(String)
        case missingValue(String)
        case invalidValue(option: String, value: String, expected: String)

        public var description: String {
            switch self {
            case .unknownOption(let option): "Unknown option: \(option)"
            case .missingValue(let option): "\(option) needs a value"
            case .invalidValue(let option, let value, let expected): "Invalid value for \(option): \(value) (expected \(expected))"
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
        var remaining = arguments[...]
        func value(for option: String) throws(ParseError) -> String {
            guard let value = remaining.popFirst(), !value.hasPrefix("-") else { throw .missingValue(option) }
            return value
        }
        while let argument = remaining.popFirst() {
            switch argument {
            case "--force", "-f":
                options.force = true
            case "--style", "-s":
                let raw = try value(for: argument)
                guard let style = Style(rawValue: raw.lowercased()) else {
                    throw .invalidValue(option: argument, value: raw, expected: "classic or short")
                }
                options.style = style
            case "--words", "-w":
                let raw = try value(for: argument)
                guard let words = Int(raw), (1...3).contains(words) else {
                    throw .invalidValue(option: argument, value: raw, expected: "1, 2 or 3")
                }
                options.words = words
            case let option where option.hasPrefix("-"):
                throw .unknownOption(option)
            default:
                mediaFiles.append(argument)
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
          -s, --style classic|short   classic: one or two lines, as in films (default)
                                      short: a few words at a time, as in short-form videos
          -w, --words 1|2|3           Words per cue in the short style (default 1)
          -f, --force                 Replace a subtitle file that already exists

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
