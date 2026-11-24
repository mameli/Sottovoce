import Foundation

/// Live status of one Media File queued through the MCP server.
public struct SubtitleJobStatus: Equatable, Sendable, Codable {
    public enum State: String, Sendable, Codable {
        case queued
        case running
        case completed
        case failed
    }

    public let mediaFile: String
    public let subtitleFile: String
    public let state: State
    public let phase: String?
    public let format: Format
    public let style: Style
    public let language: String?
    public let duration: Double?
    public let cues: Int?
    public let error: String?

    public init(
        mediaFile: String,
        subtitleFile: String,
        state: State,
        phase: String? = nil,
        format: Format,
        style: Style,
        language: String? = nil,
        duration: Double? = nil,
        cues: Int? = nil,
        error: String? = nil
    ) {
        self.mediaFile = mediaFile
        self.subtitleFile = subtitleFile
        self.state = state
        self.phase = phase
        self.format = format
        self.style = style
        self.language = language
        self.duration = duration
        self.cues = cues
        self.error = error
    }
}

/// Backend used by `MCPServer` to queue Media Files and report their status.
public protocol SubtitlingService: Sendable {
    func enqueue(mediaFile: String, options: Command.Options) -> Result<SubtitleJobStatus, Error>
    func status(forPath path: String?) -> [SubtitleJobStatus]
}

/// The Model Context Protocol server behind `sottovoce mcp`: JSON-RPC 2.0, one message per line on
/// stdin and stdout (ADR 0004, ADR 0007).
public struct MCPServer: Sendable {
    public static let protocolVersion = "2025-06-18"
    static let supportedVersions: Set<String> = ["2024-11-05", "2025-03-26", "2025-06-18"]

    private let service: any SubtitlingService
    private let version: String

    public init(service: any SubtitlingService, version: String) {
        self.service = service
        self.version = version
    }

    /// Answers every line of `input` until EOF, writing each JSON-RPC response as one line.
    public func run(readLine: () -> String?, write: (String) -> Void) {
        while let line = readLine() {
            if let answer = answer(toLine: line) { write(answer) }
        }
    }

    /// The answer to one JSON-RPC message, or `nil` for a notification.
    public func answer(toLine line: String) -> String? {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let message = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let id = message["id"] else { return nil }
        let method = message["method"] as? String ?? ""
        let params = message["params"] as? [String: Any] ?? [:]
        let response: [String: Any]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? Self.protocolVersion
            response = ["result": [
                "protocolVersion": Self.supportedVersions.contains(requested) ? requested : Self.protocolVersion,
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": "sottovoce", "version": version],
                "instructions": """
                    Sottovoce turns the speech in a local video or audio Media File on this Mac into \
                    a Subtitle File (SRT or VTT) ready for DaVinci Resolve and CapCut. Call \
                    create_subtitles with an absolute path to queue a Media File and get the Subtitle \
                    File path immediately, then poll subtitles_status until state is completed or failed.
                    """,
            ]]
        case "ping":
            response = ["result": [:] as [String: Any]]
        case "tools/list":
            response = ["result": ["tools": Self.tools]]
        case "tools/call":
            response = ["result": call(params["name"] as? String ?? "", arguments: params["arguments"] as? [String: Any] ?? [:])]
        default:
            response = ["error": ["code": -32601, "message": "Method not found: \(method)"]]
        }
        return Self.encode(response.merging(["jsonrpc": "2.0", "id": id]) { $1 })
    }

    // MARK: - Tools

    static var tools: [[String: Any]] { [
        [
            "name": "create_subtitles",
            "description": "Queues a local Media File (video or audio) to be subtitled on this Mac and returns the Subtitle File path immediately. Poll subtitles_status for completion.",
            "inputSchema": schema([
                "path": ["type": "string", "description": "Absolute path to the Media File."],
                "style": ["type": "string", "enum": ["classic", "short"], "description": "classic (default): 1-2 lines as in films; short: 1-3 words for short-form video."],
                "words": ["type": "integer", "minimum": 1, "maximum": 3, "description": "Words per Cue in the short style (1-3, default 1)."],
                "format": ["type": "string", "enum": ["srt", "vtt"], "description": "Subtitle File Format: srt (default) or vtt."],
                "speakers": ["type": "boolean", "description": "Split Cues on every Speaker change (default false)."],
                "force": ["type": "boolean", "description": "Replace an existing Subtitle File instead of failing (default false)."],
            ], required: ["path"]),
        ],
        [
            "name": "subtitles_status",
            "description": "Reports progress and completion of queued Media Files. Pass path (Media File or Subtitle File) for one job, or omit path to list all jobs in this session.",
            "inputSchema": schema([
                "path": ["type": "string", "description": "Optional Media File or Subtitle File path."],
            ]),
            "annotations": ["readOnlyHint": true],
        ],
    ] }

    private static func schema(_ properties: [String: Any], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required]
    }

    private func call(_ name: String, arguments: [String: Any]) -> [String: Any] {
        switch name {
        case "create_subtitles":
            guard let path = arguments["path"] as? String, !path.trimmingCharacters(in: .whitespaces).isEmpty else {
                return Self.toolResult("Missing required argument: path.", isError: true)
            }
            var options = Command.Options()
            if let rawStyle = arguments["style"] as? String {
                guard let style = Style(rawValue: rawStyle.lowercased()) else {
                    return Self.toolResult("Invalid style: \(rawStyle) (expected classic or short).", isError: true)
                }
                options.style = style
            }
            if let rawWords = arguments["words"] as? Int {
                guard (1...3).contains(rawWords) else {
                    return Self.toolResult("Invalid words: \(rawWords) (expected 1, 2 or 3).", isError: true)
                }
                options.words = rawWords
            }
            if let rawFormat = arguments["format"] as? String {
                guard let format = Format(rawValue: rawFormat.lowercased()) else {
                    return Self.toolResult("Invalid format: \(rawFormat) (expected srt or vtt).", isError: true)
                }
                options.format = format
            }
            if let speakers = arguments["speakers"] as? Bool {
                options.speakers = speakers
            }
            if let force = arguments["force"] as? Bool {
                options.force = force
            }
            switch service.enqueue(mediaFile: path, options: options) {
            case .success(let job):
                return Self.toolResult(Self.encodeCodable(job))
            case .failure(let error):
                return Self.toolResult("\(error)", isError: true)
            }

        case "subtitles_status":
            let path = arguments["path"] as? String
            let jobs = service.status(forPath: path)
            if let path, jobs.isEmpty {
                return Self.toolResult("No subtitle job found for \(path).", isError: true)
            }
            if path != nil, let job = jobs.first {
                return Self.toolResult(Self.encodeCodable(job))
            }
            return Self.toolResult(Self.encodeCodable(jobs))

        default:
            return Self.toolResult("Unknown tool: \(name).", isError: true)
        }
    }

    private static func toolResult(_ text: String, isError: Bool = false) -> [String: Any] {
        var result: [String: Any] = ["content": [["type": "text", "text": text]]]
        if isError { result["isError"] = true }
        return result
    }

    private static func encode(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func encodeCodable<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(value)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
