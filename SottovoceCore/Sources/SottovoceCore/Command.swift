import Foundation

/// What the `sottovoce` command was asked to do, read from its arguments. Parsing only: the app
/// runs it, since transcription needs frameworks this package does not depend on.
public enum Command: Equatable, Sendable {
    case help
    case version
    case mcp
    /// Keep running and subtitle every Media File that lands in `folder`.
    case watch(folder: String, options: Options)
    /// Subtitle each Media File, one at a time.
    case subtitle(mediaFiles: [String], options: Options)

    public struct Options: Equatable, Sendable {
        /// Replace an existing Subtitle File instead of failing.
        public var force = false
        public var style: Style = .classic
        /// Words per Cue in the Short Style.
        public var words = 1
        /// Syntax of the Subtitle File written.
        public var format: Format = .srt
        /// Print a JSON array of results on stdout instead of one path per line.
        public var json = false
        /// Opt-in Speaker diarization: split Cues on every Speaker change.
        public var speakers = false
        /// Classic Style parameters (CLI only; GUI keeps defaults).
        public var maxLineCharacters = 42
        public var maxLines = 2
        public var maxDuration: TimeInterval = 7
        public var maxCharactersPerSecond: Double = 17

        public init(
            force: Bool = false,
            style: Style = .classic,
            words: Int = 1,
            format: Format = .srt,
            json: Bool = false,
            speakers: Bool = false,
            maxLineCharacters: Int = 42,
            maxLines: Int = 2,
            maxDuration: TimeInterval = 7,
            maxCharactersPerSecond: Double = 17
        ) {
            self.force = force
            self.style = style
            self.words = words
            self.format = format
            self.json = json
            self.speakers = speakers
            self.maxLineCharacters = maxLineCharacters
            self.maxLines = maxLines
            self.maxDuration = maxDuration
            self.maxCharactersPerSecond = maxCharactersPerSecond
        }

        public var classicStyle: ClassicStyle {
            ClassicStyle(
                maxLineCharacters: maxLineCharacters,
                maxLines: maxLines,
                maxDuration: maxDuration,
                maxCharactersPerSecond: maxCharactersPerSecond
            )
        }
    }

    /// The commands that are not a Media File. Run as `Sottovoce` (inside the bundle), only these,
    /// or a path to an existing file, make the executable act as the CLI instead of the app.
    public static let names: Set<String> = ["help", "version", "mcp", "watch", "--help", "-h", "--version"]

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case unknownOption(String)
        case missingValue(String)
        case invalidValue(option: String, value: String, expected: String)
        case missingFolder

        public var description: String {
            switch self {
            case .unknownOption(let option): "Unknown option: \(option)"
            case .missingValue(let option): "\(option) needs a value"
            case .invalidValue(let option, let value, let expected): "Invalid value for \(option): \(value) (expected \(expected))"
            case .missingFolder: "watch needs a folder path"
            }
        }
    }

    public static func parse(_ arguments: [String]) throws(ParseError) -> Command {
        guard let first = arguments.first else { return .help }
        switch first {
        case "help", "--help", "-h": return .help
        case "version", "--version": return .version
        case "mcp": return .mcp
        case "watch":
            let (positionals, options) = try parseArguments(Array(arguments.dropFirst()))
            guard positionals.count == 1 else {
                if positionals.isEmpty { throw .missingFolder }
                throw .invalidValue(option: "watch", value: positionals[1], expected: "a single folder path")
            }
            return .watch(folder: positionals[0], options: options)
        default: break
        }
        let (mediaFiles, options) = try parseArguments(arguments)
        guard !mediaFiles.isEmpty else { return .help }
        return .subtitle(mediaFiles: mediaFiles, options: options)
    }

    private static func parseArguments(_ arguments: [String]) throws(ParseError) -> ([String], Options) {
        var options = Options()
        var positionals: [String] = []
        var remaining = arguments[...]
        func value(for option: String) throws(ParseError) -> String {
            guard let value = remaining.popFirst(), !value.hasPrefix("-") else { throw .missingValue(option) }
            return value
        }
        while let argument = remaining.popFirst() {
            switch argument {
            case "--force", "-f":
                options.force = true
            case "--json":
                options.json = true
            case "--speakers":
                options.speakers = true
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
            case "--format":
                let raw = try value(for: argument)
                guard let format = Format(rawValue: raw.lowercased()) else {
                    throw .invalidValue(option: argument, value: raw, expected: "srt or vtt")
                }
                options.format = format
            case "--max-line-chars":
                let raw = try value(for: argument)
                guard let chars = Int(raw), chars >= 10 else {
                    throw .invalidValue(option: argument, value: raw, expected: "an integer >= 10")
                }
                options.maxLineCharacters = chars
            case "--max-lines":
                let raw = try value(for: argument)
                guard let lines = Int(raw), (1...2).contains(lines) else {
                    throw .invalidValue(option: argument, value: raw, expected: "1 or 2")
                }
                options.maxLines = lines
            case "--max-duration":
                let raw = try value(for: argument)
                guard let seconds = Double(raw), seconds.isFinite, seconds > 0 else {
                    throw .invalidValue(option: argument, value: raw, expected: "a positive number of seconds")
                }
                options.maxDuration = seconds
            case "--max-cps":
                let raw = try value(for: argument)
                guard let cps = Double(raw), cps.isFinite, cps > 0 else {
                    throw .invalidValue(option: argument, value: raw, expected: "a positive number")
                }
                options.maxCharactersPerSecond = cps
            case let option where option.hasPrefix("-"):
                throw .unknownOption(option)
            default:
                positionals.append(argument)
            }
        }
        return (positionals, options)
    }

    public static let usage = """
        Usage:
          sottovoce <media-file>... [options]
          sottovoce watch <folder> [options]

        Writes a subtitle file next to each video or audio file, with the same name
        (interview.mov -> interview.srt), and prints its path on stdout. Progress goes
        to stderr.

        Options:
          -s, --style classic|short   classic: one or two lines, as in films (default)
                                      short: a few words at a time, as in short-form videos
          -w, --words 1|2|3           Words per cue in the short style (default 1)
              --format srt|vtt        Subtitle file format (default srt)
              --speakers              Split cues at speaker changes (Nemotron diarization)
          -f, --force                 Replace a subtitle file that already exists
              --json                  Print a JSON array of results on stdout

        Classic style options:
              --max-line-chars N      Maximum characters per line (default 42)
              --max-lines 1|2         Maximum lines per cue (default 2)
              --max-duration SECONDS  Maximum cue duration in seconds (default 7)
              --max-cps N             Target reading speed in characters/sec (default 17)

        Commands:
          watch <folder>  Keep running and subtitle every media file that lands in folder
          mcp             Run the local stdio MCP server
          help            Show this help
          version         Show the version
        """
}

/// Structured result of subtitling one Media File, printed as a JSON array with `--json`.
public struct SubtitlingResult: Equatable, Sendable, Codable {
    public let mediaFile: String
    public let subtitleFile: String?
    public let format: Format?
    public let style: Style?
    public let language: String?
    public let duration: Double?
    public let cues: Int?
    public let error: String?

    public init(
        mediaFile: String,
        subtitleFile: String? = nil,
        format: Format? = nil,
        style: Style? = nil,
        language: String? = nil,
        duration: Double? = nil,
        cues: Int? = nil,
        error: String? = nil
    ) {
        self.mediaFile = mediaFile
        self.subtitleFile = subtitleFile
        self.format = format
        self.style = style
        self.language = language
        self.duration = duration
        self.cues = cues
        self.error = error
    }

    public static func encodeJSON(_ results: [SubtitlingResult]) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(results)
        return String(decoding: data, as: UTF8.self)
    }
}

/// Exit codes of the CLI (sysexits.h where one fits).
public enum ExitCode {
    public static let ok: Int32 = 0
    public static let failure: Int32 = 1
    public static let usage: Int32 = 64
}
