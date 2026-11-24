import Foundation

/// The rule that decides how the words of the Transcript are grouped into Cues.
public enum Style: String, CaseIterable, Sendable, Codable {
    case classic
    case short
}

private let sentenceEnds: Set<Character> = [".", "?", "!", "…"]
private let clauseEnds: Set<Character> = [",", ";", ":"]

private extension Word {
    var endsSentence: Bool { text.last.map(sentenceEnds.contains) ?? false }
    var endsClause: Bool { text.last.map(clauseEnds.contains) ?? false }
}

// MARK: - Short

/// The Style of short-form vertical videos: Cues of one to three words.
public struct ShortStyle: Sendable {
    /// Words per Cue, 1 to 3.
    public let words: Int
    /// The video's frame duration, to snap Cue boundaries to frames; nil for audio only.
    public let frameDuration: TimeInterval?

    /// A gap shorter than this keeps a Cue on screen until the next one starts.
    static let hold: TimeInterval = 1.0
    /// Shortest Cue: a shorter word joins the next one, even beyond `words` (issue 02: one-word
    /// Cues of two frames flicker in fast speech).
    static let minimumDuration: TimeInterval = 0.15
    /// Removed from the end of every word; `?` and `!` stay, they change the meaning.
    static let strippedPunctuation: Set<Character> = [",", ".", ";", ":", "…"]

    public init(words: Int = 1, frameDuration: TimeInterval? = nil) {
        self.words = min(max(words, 1), 3)
        self.frameDuration = frameDuration
    }

    public func cues(_ transcript: Transcript) -> [Cue] {
        let all = transcript.words
        // 1. Group words: up to `words`, never across a sentence end or a pause.
        var groups: [[Word]] = []
        var current: [Word] = []
        for (index, word) in all.enumerated() {
            current.append(word)
            let next = index + 1 < all.count ? all[index + 1] : nil
            let pauseFollows = next.map { $0.start - word.end >= Self.hold } ?? true
            if current.count >= words || word.endsSentence || pauseFollows {
                groups.append(current)
                current = []
            }
        }
        if !current.isEmpty { groups.append(current) }

        // 2. Merge a group shown for less than the minimum into the next one, if it follows closely.
        var merged: [[Word]] = []
        var pending: [Word] = []
        for (index, group) in groups.enumerated() {
            pending += group
            let next = index + 1 < groups.count ? groups[index + 1] : nil
            guard let next, next[0].start - pending.last!.end < Self.hold else {
                merged.append(pending)
                pending = []
                continue
            }
            if next[0].start - pending[0].start >= Self.minimumDuration {
                merged.append(pending)
                pending = []
            }
        }

        // 3. Times: held until the next Cue across short gaps, snapped to frames, never shorter
        //    than the minimum (rounded up to whole frames) and never overlapping.
        let minimum = frameDuration.map { (Self.minimumDuration / $0).rounded(.up) * $0 } ?? Self.minimumDuration
        var cues: [Cue] = []
        for (index, group) in merged.enumerated() {
            let next = index + 1 < merged.count ? merged[index + 1] : nil
            var start = snap(group[0].start)
            if let previous = cues.last { start = max(start, previous.end) }
            var end = snap(group.last!.end)
            if let next, next[0].start - group.last!.end < Self.hold {
                end = snap(next[0].start)
            }
            end = max(end, start + minimum)
            let text = group.map { stripped($0.text) }.filter { !$0.isEmpty }.joined(separator: " ")
            guard !text.isEmpty else { continue }
            cues.append(Cue(start: start, end: end, text: text))
        }
        return cues
    }

    private func snap(_ time: TimeInterval) -> TimeInterval {
        guard let frameDuration else { return time }
        return (time / frameDuration).rounded() * frameDuration
    }

    private func stripped(_ word: String) -> String {
        var word = word
        while let last = word.last, Self.strippedPunctuation.contains(last) { word.removeLast() }
        return word
    }
}

// MARK: - Classic

/// The Style of films and YouTube videos: Cues of one or two Lines, split on pauses and punctuation.
public struct ClassicStyle: Sendable {
    public var maxLineCharacters = 42
    public var maxLines = 2
    public var maxDuration: TimeInterval = 7
    public var minDuration: TimeInterval = 1
    public var maxCharactersPerSecond: Double = 17
    /// A pause this long between two words always starts a new Cue.
    public var pause: TimeInterval = 1.0

    public init() {}

    public func cues(_ transcript: Transcript) -> [Cue] {
        let groups = group(transcript.words)
        var cues: [Cue] = []
        for (index, words) in groups.enumerated() {
            let start = words[0].start
            let text = lines(words.map(\.text))
            let characters = Double(text.replacingOccurrences(of: "\n", with: " ").count)
            // Long enough to be read and at least the minimum, without reaching the next Cue.
            var end = max(words.last!.end, start + minDuration, start + characters / maxCharactersPerSecond)
            end = min(end, start + max(maxDuration, words.last!.end - start))
            end = max(end, words.last!.end)
            // Never into the next Cue, even when the recognizer let a word run past the next one's start.
            if index + 1 < groups.count {
                end = min(end, groups[index + 1][0].start)
            }
            cues.append(Cue(start: start, end: max(end, start + 0.001), text: text))
        }
        return cues
    }

    /// Splits the words into Cues. A sentence end or a pause always closes one; in between, the
    /// cut points are chosen together (dynamic programming) so that each Cue fits, there are as few
    /// Cues as possible, they end at punctuation when they can, and no Cue is a stray fragment.
    func group(_ words: [Word]) -> [[Word]] {
        var runs: [[Word]] = []
        var current: [Word] = []
        for word in words {
            if let previous = current.last, word.start - previous.end >= pause {
                runs.append(current)
                current = []
            }
            current.append(word)
            if word.endsSentence {
                runs.append(current)
                current = []
            }
        }
        if !current.isEmpty { runs.append(current) }
        return runs.flatMap(split)
    }

    /// The best partition of one run of words into Cues that fit.
    private func split(_ run: [Word]) -> [[Word]] {
        let n = run.count
        var cost = [Double](repeating: .infinity, count: n + 1)
        var cut = [Int](repeating: 0, count: n + 1)
        cost[0] = 0
        for end in 1...n {
            for start in stride(from: end - 1, through: 0, by: -1) {
                let candidate = Array(run[start..<end])
                guard candidate.count == 1 || fits(candidate) else { break }
                let total = cost[start] + penalty(candidate, isLast: end == n)
                if total < cost[end] {
                    cost[end] = total
                    cut[end] = start
                }
            }
        }
        var groups: [[Word]] = []
        var end = n
        while end > 0 {
            groups.insert(Array(run[cut[end]..<end]), at: 0)
            end = cut[end]
        }
        return groups
    }

    /// One per Cue, plus a cost for ending away from punctuation and for a fragment too short to
    /// stand on its own.
    private func penalty(_ words: [Word], isLast: Bool) -> Double {
        let characters = words.map(\.text.count).reduce(0, +) + words.count - 1
        var cost = 1.0
        if !isLast, !(words.last!.endsClause || words.last!.endsSentence) { cost += 0.6 }
        let fragment = maxLineCharacters / 2
        if characters < fragment { cost += 0.4 * Double(fragment - characters) / Double(fragment) }
        return cost
    }

    private func fits(_ words: [Word]) -> Bool {
        guard words.last!.end - words[0].start <= maxDuration else { return false }
        return lineBreak(words.map(\.text)) != nil
    }

    /// The text of a Cue with its Lines separated by `\n`; a single word longer than a Line stays whole.
    func lines(_ words: [String]) -> String {
        lineBreak(words) ?? words.joined(separator: " ")
    }

    /// The most balanced split into at most `maxLines` Lines within `maxLineCharacters`, preferring
    /// to break after punctuation; nil when the words do not fit.
    func lineBreak(_ words: [String]) -> String? {
        let single = words.joined(separator: " ")
        if single.count <= maxLineCharacters { return single }
        guard maxLines >= 2, words.count >= 2 else { return nil }
        var best: (score: Int, text: String)?
        for split in 1..<words.count {
            let first = words[..<split].joined(separator: " ")
            let second = words[split...].joined(separator: " ")
            guard first.count <= maxLineCharacters, second.count <= maxLineCharacters else { continue }
            let afterPunctuation = words[split - 1].last.map { sentenceEnds.contains($0) || clauseEnds.contains($0) } ?? false
            // Balanced lines; a bottom-heavy shape and a break after punctuation are preferred.
            let score = abs(first.count - second.count) + (first.count > second.count ? 2 : 0) - (afterPunctuation ? 8 : 0)
            if best == nil || score < best!.score {
                best = (score, first + "\n" + second)
            }
        }
        return best?.text
    }
}
