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

    @Test func styleAndWords() throws {
        #expect(try Command.parse(["a.mov", "--style", "short", "-w", "2"])
            == .subtitle(mediaFiles: ["a.mov"], options: .init(style: .short, words: 2)))
    }

    @Test func invalidValuesAreRejected() {
        #expect(throws: Command.ParseError.invalidValue(option: "--words", value: "4", expected: "1, 2 or 3")) {
            try Command.parse(["a.mov", "--words", "4"])
        }
        #expect(throws: Command.ParseError.missingValue("--style")) {
            try Command.parse(["a.mov", "--style"])
        }
    }

    @Test func unknownOptionIsRejected() {
        #expect(throws: Command.ParseError.unknownOption("--nope")) {
            try Command.parse(["a.mov", "--nope"])
        }
    }
}
