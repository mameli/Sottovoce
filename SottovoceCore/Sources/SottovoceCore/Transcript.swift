import Foundation

/// A piece of text from the recognizer with its times, in seconds from the start of the Media
/// File. Parakeet gives sub-word tokens that carry their own leading space.
public struct TimedToken: Equatable, Sendable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// One word of the Transcript, with its own start and end time.
public struct Word: Equatable, Sendable, Codable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// The words spoken in a Media File, in order.
public struct Transcript: Equatable, Sendable {
    public let words: [Word]

    public init(words: [Word]) {
        self.words = words
    }

    /// Joins sub-word tokens into words: a token starting with a space (or SentencePiece's `▁`)
    /// starts a new word; the others continue the current one, punctuation included.
    public init(tokens: [TimedToken]) {
        var words: [Word] = []
        var text = ""
        var start: TimeInterval = 0
        var end: TimeInterval = 0
        func close() {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { words.append(Word(text: trimmed, start: start, end: end)) }
            text = ""
        }
        for token in tokens {
            let piece = token.text.replacingOccurrences(of: "▁", with: " ")
            if piece.hasPrefix(" ") || text.isEmpty {
                close()
                start = token.start
            }
            text += piece
            end = token.end
        }
        close()
        self.words = words
    }
}
