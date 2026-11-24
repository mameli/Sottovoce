import Foundation
import Testing
@testable import SottovoceCore

private final class StubSubtitlingService: SubtitlingService, @unchecked Sendable {
    struct StubError: Error, CustomStringConvertible { let description: String }

    var jobs: [String: SubtitleJobStatus] = [:]
    var failNext: String?

    func enqueue(mediaFile: String, options: Command.Options) -> Result<SubtitleJobStatus, Error> {
        if let failNext {
            return .failure(StubError(description: failNext))
        }
        let subtitle = SubtitleFile.url(for: URL(filePath: mediaFile), format: options.format).path(percentEncoded: false)
        let job = SubtitleJobStatus(
            mediaFile: mediaFile,
            subtitleFile: subtitle,
            state: .queued,
            phase: "queued",
            format: options.format,
            style: options.style
        )
        jobs[mediaFile] = job
        return .success(job)
    }

    func status(forPath path: String?) -> [SubtitleJobStatus] {
        guard let path else { return Array(jobs.values) }
        if let job = jobs[path] { return [job] }
        if let job = jobs.values.first(where: { $0.subtitleFile == path }) { return [job] }
        return []
    }
}

@Suite struct MCPServerTests {
    private func parse(_ line: String?) throws -> [String: Any] {
        let text = try #require(line)
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    @Test func commandParsesMcp() throws {
        #expect(try Command.parse(["mcp"]) == .mcp)
        #expect(Command.names.contains("mcp"))
        #expect(Command.usage.contains("mcp"))
    }

    @Test func initializeAndPingAndNotifications() throws {
        let server = MCPServer(service: StubSubtitlingService(), version: "0.1.0")
        let initResp = try parse(server.answer(toLine: #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#))
        let result = try #require(initResp["result"] as? [String: Any])
        #expect(result["protocolVersion"] as? String == "2025-03-26")
        let info = try #require(result["serverInfo"] as? [String: Any])
        #expect(info["name"] as? String == "sottovoce")
        #expect(info["version"] as? String == "0.1.0")

        // Notifications (no id) produce no reply.
        #expect(server.answer(toLine: #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)

        // Ping returns empty result.
        let pingResp = try parse(server.answer(toLine: #"{"jsonrpc":"2.0","id":2,"method":"ping"}"#))
        #expect(pingResp["result"] != nil)
    }

    @Test func toolsListExposesCreateAndStatus() throws {
        let server = MCPServer(service: StubSubtitlingService(), version: "0.1.0")
        let resp = try parse(server.answer(toLine: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#))
        let result = try #require(resp["result"] as? [String: Any])
        let tools = try #require(result["tools"] as? [[String: Any]])
        #expect(tools.compactMap { $0["name"] as? String } == ["create_subtitles", "subtitles_status"])
    }

    @Test func createSubtitlesAndQueryStatus() throws {
        let stub = StubSubtitlingService()
        let server = MCPServer(service: stub, version: "0.1.0")

        let createResp = try parse(server.answer(toLine: """
            {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create_subtitles","arguments":{"path":"/v/clip.mov","style":"short","words":2,"format":"vtt"}}}
            """))
        let createResult = try #require(createResp["result"] as? [String: Any])
        #expect(createResult["isError"] == nil)
        let content = try #require((createResult["content"] as? [[String: Any]])?.first?["text"] as? String)
        let queued = try JSONDecoder().decode(SubtitleJobStatus.self, from: Data(content.utf8))
        #expect(queued.subtitleFile == "/v/clip.vtt")
        #expect(queued.state == .queued)
        #expect(queued.style == .short)
        #expect(queued.format == .vtt)

        // Query by subtitleFile path works too.
        let statusResp = try parse(server.answer(toLine: """
            {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"subtitles_status","arguments":{"path":"/v/clip.vtt"}}}
            """))
        let statusResult = try #require(statusResp["result"] as? [String: Any])
        let statusText = try #require((statusResult["content"] as? [[String: Any]])?.first?["text"] as? String)
        let fetched = try JSONDecoder().decode(SubtitleJobStatus.self, from: Data(statusText.utf8))
        #expect(fetched == queued)
    }

    @Test func invalidToolArgumentsReturnIsError() throws {
        let server = MCPServer(service: StubSubtitlingService(), version: "0.1.0")
        let resp = try parse(server.answer(toLine: """
            {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"create_subtitles","arguments":{"path":"/v/a.mov","format":"ass"}}}
            """))
        let result = try #require(resp["result"] as? [String: Any])
        #expect(result["isError"] as? Bool == true)
    }
}
