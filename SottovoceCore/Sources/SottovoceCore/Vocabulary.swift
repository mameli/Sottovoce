import Foundation

/// The terms speech recognition gets wrong, read from `~/.sottovoce/vocabulary.md` in the same
/// format as Takku's `~/.takku/vocabulary.md` (`- Term = variant, variant | description`), never
/// read from Takku automatically.
public struct Vocabulary: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let term: String
        public let variants: [String]
        public let description: String?

        public init(term: String, variants: [String] = [], description: String? = nil) {
            self.term = term
            self.variants = variants
            self.description = description
        }
    }

    public static let empty = Vocabulary(fileContent: "")

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".sottovoce/vocabulary.md")
    }

    /// Written when the user opens Vocabulary in Settings and the file does not exist yet.
    public static let exampleFileContent = """
        # Vocabulary

        Names, acronyms and technical words that speech recognition gets wrong. Sottovoce fixes the variants in every Transcript.

        One entry per line, starting with `- `: the correct term, then after `=` the variants usually heard instead (optional, comma-separated), then after `|` a short description (optional). Example: `- Scaleway = scale uai | our EU cloud provider`

        Lines that are not entries, like this text, are ignored.

        """

    public let entries: [Entry]

    public init(fileContent: String) {
        var seenTerms = Set<String>()
        var seenVariants = Set<String>()
        var entries: [Entry] = []
        for line in fileContent.split(whereSeparator: \.isNewline) where line.hasPrefix("- ") {
            let (rest, description) = Self.split(line.dropFirst(2), on: "|")
            let (term, variants) = Self.split(rest, on: "=")
            guard !term.isEmpty, seenTerms.insert(term.lowercased()).inserted else { continue }
            let kept = (variants?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? [])
                .filter { !$0.isEmpty && $0 != term && seenVariants.insert($0.lowercased()).inserted }
            entries.append(Entry(term: term, variants: kept, description: description?.isEmpty == true ? nil : description))
        }
        self.entries = entries
    }

    public static func load(from url: URL = defaultURL) -> Vocabulary {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return .empty }
        return Vocabulary(fileContent: content)
    }

    /// Replaces single-word and multi-word variants in `transcript` with their canonical term,
    /// preserving per-word timestamps, Speakers, and surrounding punctuation.
    public func applying(to transcript: Transcript) -> Transcript {
        let rules = wordRules()
        guard !rules.isEmpty, !transcript.words.isEmpty else { return transcript }

        let words = transcript.words
        let parts = words.map(Self.splitPunctuation)
        var result: [Word] = []
        var i = 0
        while i < words.count {
            var matched = false
            for rule in rules {
                let count = rule.tokens.count
                guard i + count <= words.count else { continue }
                var ok = true
                for k in 0..<count {
                    if parts[i + k].core.lowercased() != rule.tokens[k] {
                        ok = false
                        break
                    }
                    // Internal punctuation or a speaker change stops a multi-word match.
                    if k + 1 < count {
                        if !parts[i + k].trailing.isEmpty || !parts[i + k + 1].leading.isEmpty {
                            ok = false
                            break
                        }
                        if words[i + k].speaker != words[i + k + 1].speaker {
                            ok = false
                            break
                        }
                    }
                }
                if ok {
                    let text = parts[i].leading + rule.term + parts[i + count - 1].trailing
                    result.append(Word(
                        text: text,
                        start: words[i].start,
                        end: words[i + count - 1].end,
                        speaker: words[i].speaker
                    ))
                    i += count
                    matched = true
                    break
                }
            }
            if !matched {
                result.append(words[i])
                i += 1
            }
        }
        return Transcript(words: result)
    }

    private struct WordRule {
        let tokens: [String]
        let term: String
    }

    /// Longest multi-word variants first so "scale uai cloud" wins over "scale uai".
    private func wordRules() -> [WordRule] {
        var rules: [WordRule] = []
        for entry in entries {
            for variant in entry.variants {
                let tokens = variant.split(whereSeparator: \.isWhitespace).map { $0.lowercased() }
                if !tokens.isEmpty {
                    rules.append(WordRule(tokens: tokens, term: entry.term))
                }
            }
        }
        return rules.sorted {
            if $0.tokens.count != $1.tokens.count { return $0.tokens.count > $1.tokens.count }
            return $0.tokens.joined(separator: " ").count > $1.tokens.joined(separator: " ").count
        }
    }

    private static func splitPunctuation(_ word: Word) -> (leading: String, core: String, trailing: String) {
        let text = word.text
        let punct = CharacterSet.punctuationCharacters
        var start = text.startIndex
        while start < text.endIndex, text[start].unicodeScalars.allSatisfy({ punct.contains($0) }) {
            start = text.index(after: start)
        }
        var end = text.endIndex
        while end > start {
            let prev = text.index(before: end)
            if text[prev].unicodeScalars.allSatisfy({ punct.contains($0) }) {
                end = prev
            } else {
                break
            }
        }
        return (String(text[..<start]), String(text[start..<end]), String(text[end...]))
    }

    private static func split(_ text: some StringProtocol, on separator: Character) -> (String, String?) {
        guard let index = text.firstIndex(of: separator) else {
            return (text.trimmingCharacters(in: .whitespaces), nil)
        }
        return (
            text[..<index].trimmingCharacters(in: .whitespaces),
            text[text.index(after: index)...].trimmingCharacters(in: .whitespaces)
        )
    }
}
