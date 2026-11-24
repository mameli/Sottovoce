import Foundation

/// One timed entry of a Subtitle File: the text shown on screen, with its start and end time.
/// Lines are separated by `\n` in `text`.
public struct Cue: Equatable, Sendable {
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// A pause this long between two words ends the sentence even without punctuation.
private let sentencePause: TimeInterval = 1.5
private let sentenceEnds: Set<Character> = [".", "?", "!", "…"]

extension Transcript {
    /// One Cue per sentence: the tracer bullet's grouping until the Styles exist (issues 09, 10).
    public func sentenceCues() -> [Cue] {
        var cues: [Cue] = []
        var current: [Word] = []
        func close() {
            guard let first = current.first, let last = current.last else { return }
            cues.append(Cue(start: first.start, end: last.end, text: current.map(\.text).joined(separator: " ")))
            current = []
        }
        for word in words {
            if let previous = current.last, word.start - previous.end >= sentencePause {
                close()
            }
            current.append(word)
            if let last = word.text.last, sentenceEnds.contains(last) {
                close()
            }
        }
        close()
        return cues
    }
}
