import Foundation

/// A stretch in which one voice speaks, as diarization heard it. `voice` is the diarizer's own id;
/// times in seconds from the start of the Media File.
public struct SpeakerTurn: Equatable, Codable, Sendable {
    public let voice: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(voice: String, start: TimeInterval, end: TimeInterval) {
        self.voice = voice
        self.start = start
        self.end = end
    }
}

/// A short word ("ok", "sì") is often too brief for diarization to count as a turn: it takes the
/// voice of a turn this close, otherwise it stays without a Speaker.
private let nearestTurnTolerance: TimeInterval = 2

/// Gives each Word the Speaker whose turns cover most of it (or the nearest turn within 2 s).
/// Speakers are numbered 1, 2, … in the order they first speak in the Transcript.
public func assigningSpeakers(to transcript: Transcript, turns: [SpeakerTurn]) -> Transcript {
    Transcript(words: assigningSpeakers(to: transcript.words, turns: turns))
}

public func assigningSpeakers(to words: [Word], turns: [SpeakerTurn]) -> [Word] {
    guard !turns.isEmpty else { return words }
    let voices = words.map { voice(of: $0, in: turns) }
    var numbers: [String: Int] = [:]
    for index in words.indices.sorted(by: { words[$0].start < words[$1].start }) {
        if let voice = voices[index], numbers[voice] == nil {
            numbers[voice] = numbers.count + 1
        }
    }
    return zip(words, voices).map { word, voice in
        Word(text: word.text, start: word.start, end: word.end, speaker: voice.flatMap { numbers[$0] })
    }
}

private func voice(of word: Word, in turns: [SpeakerTurn]) -> String? {
    var overlap: [String: TimeInterval] = [:]
    for turn in turns {
        let shared = min(word.end, turn.end) - max(word.start, turn.start)
        if shared > 0 { overlap[turn.voice, default: 0] += shared }
    }
    if let longest = overlap.max(by: { $0.value < $1.value }) { return longest.key }

    func distance(_ turn: SpeakerTurn) -> TimeInterval {
        max(turn.start - word.end, word.start - turn.end)
    }
    return turns
        .filter { distance($0) <= nearestTurnTolerance }
        .min { distance($0) < distance($1) }?
        .voice
}
