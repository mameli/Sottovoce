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

    @Test func unknownOptionIsRejected() {
        #expect(throws: Command.ParseError.unknownOption("--nope")) {
            try Command.parse(["a.mov", "--nope"])
        }
    }
}
