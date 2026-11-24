import Foundation
import Testing
@testable import SottovoceCore

/// Words spoken back to back, each `duration` long, starting at `start`.
private func spoken(_ text: String, start: TimeInterval = 0, duration: TimeInterval = 0.3, gap: TimeInterval = 0) -> [Word] {
    var time = start
    return text.split(separator: " ").map { piece in
        defer { time += duration + gap }
        return Word(text: String(piece), start: time, end: time + duration)
    }
}

private let ntsc = 1001.0 / 30000

@Suite struct ShortStyleTests {
    @Test func oneWordPerCueHeldUntilTheNext() {
        let cues = ShortStyle().cues(Transcript(words: spoken("Amici bentornati sul canale", gap: 0.2)))
        #expect(cues.map(\.text) == ["Amici", "bentornati", "sul", "canale"])
        for (a, b) in zip(cues, cues.dropFirst()) {
            #expect(a.end == b.start)
        }
        #expect(abs(cues.last!.end - 1.8) < 1e-9)
    }

    @Test func pauseOfOneSecondOrMoreLeavesTheScreenEmpty() {
        let words = [Word(text: "allora...", start: 0, end: 0.4), Word(text: "iniziamo", start: 1.6, end: 2.1)]
        let cues = ShortStyle().cues(Transcript(words: words))
        #expect(cues[0].end == 0.4)
        #expect(cues[1].start == 1.6)
    }

    @Test func trailingCommasAndFullStopsAreRemovedQuestionMarksStay() {
        let words = spoken("Ciao, come va? Bene.")
        #expect(ShortStyle().cues(Transcript(words: words)).map(\.text) == ["Ciao", "come", "va?", "Bene"])
    }

    @Test func upToThreeWordsButNeverAcrossASentence() {
        let words = spoken("uno due tre quattro. cinque sei")
        #expect(ShortStyle(words: 3).cues(Transcript(words: words)).map(\.text) == ["uno due tre", "quattro", "cinque sei"])
    }

    @Test func tooShortWordJoinsTheNextOne() {
        // "a" is shown for 0.08 s before "casa" starts: below the 0.15 s minimum.
        let words = [
            Word(text: "vado", start: 0, end: 0.3),
            Word(text: "a", start: 0.3, end: 0.38),
            Word(text: "casa", start: 0.38, end: 0.8),
        ]
        #expect(ShortStyle().cues(Transcript(words: words)).map(\.text) == ["vado", "a casa"])
    }

    @Test(arguments: [24000.0 / 1001, 25, 30000.0 / 1001])
    func boundariesSnapToFramesAndLastAtLeastTheMinimum(fps: Double) {
        let frame = 1 / fps
        let words = spoken("uno due tre quattro cinque sei", start: 0.013, duration: 0.17, gap: 0.01)
        let cues = ShortStyle(frameDuration: frame).cues(Transcript(words: words))
        let minimumFrames = (0.15 / frame).rounded(.up)
        for cue in cues {
            let startFrames = cue.start / frame, endFrames = cue.end / frame
            #expect(abs(startFrames - startFrames.rounded()) < 1e-6)
            #expect(abs(endFrames - endFrames.rounded()) < 1e-6)
            #expect((endFrames - startFrames).rounded() >= minimumFrames)
        }
        for (a, b) in zip(cues, cues.dropFirst()) {
            #expect(b.start >= a.end - 1e-9)
        }
    }

    @Test func audioOnlyIsNotSnapped() {
        let words = [Word(text: "ciao", start: 0.0123, end: 0.4567)]
        let cue = ShortStyle(frameDuration: nil).cues(Transcript(words: words))[0]
        #expect(cue.start == 0.0123)
        #expect(cue.end == 0.4567)
    }
}

@Suite struct ClassicStyleTests {
    @Test func shortSentenceIsOneLine() {
        let cues = ClassicStyle().cues(Transcript(words: spoken("Amici, bentornati sul canale.")))
        #expect(cues.map(\.text) == ["Amici, bentornati sul canale."])
    }

    @Test func linesNeverExceedFortyTwoCharactersAndCuesTwoLines() {
        let text = "È sempre più difficile trovare nuova oggettistica per le vostre prossime avventure però ci sono state delle nuove aggiunte al mio arsenale quindi andiamole a vedere"
        let cues = ClassicStyle().cues(Transcript(words: spoken(text, duration: 0.25)))
        #expect(cues.count > 1)
        for cue in cues {
            let lines = cue.text.split(separator: "\n")
            #expect(lines.count <= 2)
            #expect(lines.allSatisfy { $0.count <= 42 })
        }
        #expect(cues.flatMap { $0.text.split(whereSeparator: { $0 == " " || $0 == "\n" }) }.joined(separator: " ") == text)
    }

    @Test func sentenceEndAndPauseCloseACue() {
        var words = spoken("Ciao. Come va")
        words.append(Word(text: "dopo", start: 3, end: 3.3))
        #expect(ClassicStyle().cues(Transcript(words: words)).map(\.text) == ["Ciao.", "Come va", "dopo"])
    }

    @Test func noCueLongerThanSevenSecondsOfSpeech() {
        let words = spoken(Array(repeating: "uh", count: 40).joined(separator: " "), duration: 0.3)
        for cue in ClassicStyle().cues(Transcript(words: words)) {
            #expect(cue.end - cue.start <= 7 + 1e-9)
        }
    }

    @Test func shortCueStaysAtLeastOneSecondAndLongEnoughToRead() {
        let words = [
            Word(text: "Sì.", start: 0, end: 0.2),
            Word(text: "Questa frase è piuttosto lunga da leggere.", start: 5, end: 5.5),
        ]
        let cues = ClassicStyle().cues(Transcript(words: words))
        #expect(cues[0].end == 1.0)
        // 42 characters at 17 per second need about 2.5 s.
        #expect(cues[1].end - cues[1].start >= 42.0 / 17 - 1e-9)
    }

    @Test func extendingNeverOverlapsTheNextCue() {
        let words = [Word(text: "Sì.", start: 0, end: 0.2), Word(text: "No.", start: 0.5, end: 0.7)]
        let cues = ClassicStyle().cues(Transcript(words: words))
        #expect(cues[0].end == 0.5)
    }

    @Test func longSentenceSplitsAtItsCommaRatherThanFillingCues() {
        let text = "Ne ho utilizzati diversi in questi anni di viaggi, e ho capito che a due cose non ho più voglia di rinunciare."
        let cues = ClassicStyle().cues(Transcript(words: spoken(text, duration: 0.2)))
        #expect(cues.map { $0.text.replacingOccurrences(of: "\n", with: " ") } == [
            "Ne ho utilizzati diversi in questi anni di viaggi,",
            "e ho capito che a due cose non ho più voglia di rinunciare.",
        ])
    }

    @Test func recognizerOverlapNeverMakesCuesOverlap() {
        let words = [Word(text: "Yes.", start: 0, end: 0.6), Word(text: "No.", start: 0.5, end: 0.9)]
        let cues = ClassicStyle().cues(Transcript(words: words))
        #expect(cues[0].end <= cues[1].start)
    }

    @Test func prefersBreakingAfterAComma() {
        let style = ClassicStyle()
        let text = style.lines("Partendo da quello che è forse, l'accessorio più utile di tutti".split(separator: " ").map(String.init))
        #expect(text == "Partendo da quello che è forse,\nl'accessorio più utile di tutti")
    }

    @Test func wordLongerThanALineStaysWhole() {
        let long = String(repeating: "a", count: 50)
        let cues = ClassicStyle().cues(Transcript(words: [Word(text: long, start: 0, end: 1)]))
        #expect(cues.map(\.text) == [long])
    }
}
