import Foundation
import SottovoceCore
@preconcurrency import Translation

/// On-device translation of Classic Cues using Apple's Translation framework (ADR 0006).
/// Headless translation (`TranslationSession(installedSource:target:)`) requires macOS 26+.
enum Translator {
    enum Failure: Error, CustomStringConvertible {
        case requiresMacOS26
        case classicOnly
        case unknownSourceLanguage
        case languageNotInstalled(source: String, target: String)
        case unsupportedPair(source: String, target: String)

        var description: String {
            switch self {
            case .requiresMacOS26:
                "on-device translation requires macOS 26 or later"
            case .classicOnly:
                "translation is only supported with the classic style"
            case .unknownSourceLanguage:
                "could not detect the spoken language to translate from"
            case .languageNotInstalled(let source, let target):
                "translation languages (\(source) -> \(target)) are not installed: open Sottovoce → Settings → Translation or macOS System Settings → General → Language & Region → Translation Languages to download them"
            case .unsupportedPair(let source, let target):
                "translation from \(source) to \(target) is not supported on this Mac"
            }
        }
    }

    static let commonLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("it", "Italian"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("pt", "Portuguese"),
        ("nl", "Dutch"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh-Hans", "Chinese (Simplified)"),
    ]

    static func translate(
        _ cues: [Cue],
        from sourceCode: String?,
        to targetCode: String,
        style: ClassicStyle
    ) async throws -> [Cue] {
        guard !cues.isEmpty else { return [] }
        guard let sourceCode, !sourceCode.isEmpty else {
            throw Failure.unknownSourceLanguage
        }
        if sourceCode.lowercased() == targetCode.lowercased() {
            return cues
        }
        guard #available(macOS 26.0, *) else {
            throw Failure.requiresMacOS26
        }
        let source = Locale.Language(identifier: sourceCode)
        let target = Locale.Language(identifier: targetCode)
        let availability = LanguageAvailability()
        let status = await availability.status(from: source, to: target)
        switch status {
        case .installed:
            break
        case .supported:
            throw Failure.languageNotInstalled(source: sourceCode, target: targetCode)
        case .unsupported:
            throw Failure.unsupportedPair(source: sourceCode, target: targetCode)
        @unknown default:
            throw Failure.unsupportedPair(source: sourceCode, target: targetCode)
        }

        let session = TranslationSession(installedSource: source, target: target)
        let requests = cues.enumerated().map { index, cue in
            TranslationSession.Request(
                sourceText: cue.text.replacingOccurrences(of: "\n", with: " "),
                clientIdentifier: String(index)
            )
        }
        let responses = try await session.translations(from: requests)
        var byIndex: [Int: String] = [:]
        for response in responses {
            if let id = response.clientIdentifier, let index = Int(id) {
                byIndex[index] = response.targetText
            }
        }
        return cues.enumerated().map { index, cue in
            let translated = byIndex[index] ?? cue.text
            let words = translated.split(whereSeparator: \.isWhitespace).map(String.init)
            let wrapped = words.isEmpty ? translated : style.lines(words)
            return Cue(start: cue.start, end: cue.end, text: wrapped)
        }
    }
}
