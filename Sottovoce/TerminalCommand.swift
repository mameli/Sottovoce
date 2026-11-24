import Foundation
import SottovoceCore

/// `sottovoce …` (a link to the executable, as Homebrew will install it) or
/// `Sottovoce.app/Contents/MacOS/Sottovoce …`: runs the CLI without opening a window and exits
/// (ADR 0004). Run as `sottovoce`, every argument goes to the CLI, so a mistyped one prints the
/// usage instead of opening the app; run as `Sottovoce`, the CLI runs only for one of its command
/// names or an existing file, and anything else (Xcode's and Finder's flags included) opens the app.
enum TerminalCommand {
    static func runIfRequested() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let calledAsCLI = URL(filePath: CommandLine.arguments[0]).lastPathComponent == "sottovoce"
        let first = arguments.first
        let looksLikeCLI = first.map { Command.names.contains($0) || FileManager.default.fileExists(atPath: $0) } ?? false
        guard calledAsCLI || looksLikeCLI else { return }
        runFromBundleIfLinked()
        exit(run(arguments))
    }

    static func run(_ arguments: [String]) -> Int32 {
        let command: Command
        do {
            command = try Command.parse(arguments)
        } catch {
            printError("\(error)\n\n\(Command.usage)")
            return ExitCode.usage
        }
        switch command {
        case .help:
            print(Command.usage)
            return ExitCode.ok
        case .version:
            print(appVersion)
            return ExitCode.ok
        case .mcp:
            let service = MCPSubtitlingService()
            let server = MCPServer(service: service, version: appVersion)
            server.run(readLine: { Swift.readLine() }, write: { line in
                FileHandle.standardOutput.write(Data((line + "\n").utf8))
            })
            return ExitCode.ok
        case .watch(let folder, let options):
            return waitFor { await WatchedFolder.run(folder, options: options) }
        case .subtitle(let mediaFiles, let options):
            return waitFor { await Subtitling.run(mediaFiles, options: options) }
        }
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Runs async work to the end from the synchronous start of the process (the app's `init`),
    /// before any window exists.
    private static func waitFor(_ work: @escaping @Sendable () async -> Int32) -> Int32 {
        final class Box: @unchecked Sendable { var value = ExitCode.failure }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            box.value = await work()
            done.signal()
        }
        done.wait()
        return box.value
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    /// Started through a link, the executable does not find its bundle, and with it the version:
    /// it runs again from its path inside Sottovoce.app (same as Takku).
    private static func runFromBundleIfLinked() {
        var size: UInt32 = 0
        _NSGetExecutablePath(nil, &size)
        var path = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&path, &size) == 0 else { return }
        let started = String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        let resolved = URL(filePath: started).resolvingSymlinksInPath().path(percentEncoded: false)
        guard resolved != started else { return }
        execv(resolved, CommandLine.unsafeArgv)
    }
}
