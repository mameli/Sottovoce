import Foundation
import Testing
@testable import SottovoceCore

@Suite struct CommandTests {
    @Test func noArgumentsShowsHelp() throws {
        #expect(try Command.parse([]) == .help)
    }

    @Test(arguments: ["help", "--help", "-h"])
    func helpAliases(_ argument: String) throws {
        #expect(try Command.parse([argument]) == .help)
    }

    @Test(arguments: ["version", "--version"])
    func versionAliases(_ argument: String) throws {
        #expect(try Command.parse([argument]) == .version)
    }

    @Test func mediaFilesInOrder() throws {
        #expect(try Command.parse(["b.mov", "a.mp4"]) == .subtitle(mediaFiles: ["b.mov", "a.mp4"], options: .init()))
    }

    @Test func forceAnywhere() throws {
        #expect(try Command.parse(["--force", "a.mov"]) == .subtitle(mediaFiles: ["a.mov"], options: .init(force: true)))
        #expect(try Command.parse(["a.mov", "-f"]) == .subtitle(mediaFiles: ["a.mov"], options: .init(force: true)))
    }

    @Test func styleWordsFormatAndJson() throws {
        #expect(try Command.parse(["a.mov", "--style", "short", "-w", "2", "--format", "vtt", "--json"])
            == .subtitle(mediaFiles: ["a.mov"], options: .init(style: .short, words: 2, format: .vtt, json: true)))
    }

    @Test func invalidValuesAreRejected() {
        #expect(throws: Command.ParseError.invalidValue(option: "--words", value: "4", expected: "1, 2 or 3")) {
            try Command.parse(["a.mov", "--words", "4"])
        }
        #expect(throws: Command.ParseError.invalidValue(option: "--format", value: "ass", expected: "srt or vtt")) {
            try Command.parse(["a.mov", "--format", "ass"])
        }
        #expect(throws: Command.ParseError.missingValue("--style")) {
            try Command.parse(["a.mov", "--style"])
        }
        #expect(throws: Command.ParseError.missingValue("--format")) {
            try Command.parse(["a.mov", "--format"])
        }
    }

    @Test func unknownOptionIsRejected() {
        #expect(throws: Command.ParseError.unknownOption("--nope")) {
            try Command.parse(["a.mov", "--nope"])
        }
    }

    @Test func usageDocumentsEveryOption() {
        for option in ["--style", "--words", "--format", "--force", "--json"] {
            #expect(Command.usage.contains(option))
        }
    }

    @Test func jsonEncodingRoundTripsResults() throws {
        let results = [
            SubtitlingResult(
                mediaFile: "/tmp/a.mov",
                subtitleFile: "/tmp/a.vtt",
                format: .vtt,
                style: .classic,
                language: "it",
                duration: 12.5,
                cues: 4
            ),
            SubtitlingResult(
                mediaFile: "/tmp/missing.mov",
                error: "file not found"
            ),
        ]
        let json = try SubtitlingResult.encodeJSON(results)
        let decoded = try JSONDecoder().decode([SubtitlingResult].self, from: Data(json.utf8))
        #expect(decoded == results)
        #expect(!json.contains("\\/"))
    }
}
