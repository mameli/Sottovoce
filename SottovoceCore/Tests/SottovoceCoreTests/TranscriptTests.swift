import Foundation
import Testing
@testable import SottovoceCore

@Suite struct TranscriptTests {
    @Test func tokensWithLeadingSpaceStartWords() {
        let tokens = [
            TimedToken(text: " Ami", start: 0.0, end: 0.24),
            TimedToken(text: "ci", start: 0.24, end: 0.40),
            TimedToken(text: " ben", start: 0.48, end: 0.64),
            TimedToken(text: "tornati", start: 0.64, end: 0.96),
            TimedToken(text: ",", start: 0.96, end: 1.04),
        ]
        #expect(Transcript(tokens: tokens).words == [
            Word(text: "Amici", start: 0.0, end: 0.40),
            Word(text: "bentornati,", start: 0.48, end: 1.04),
        ])
    }

    @Test func firstTokenWithoutSpaceAndSentencePieceMarker() {
        let tokens = [
            TimedToken(text: "Hello", start: 0, end: 0.3),
            TimedToken(text: "▁world", start: 0.4, end: 0.7),
        ]
        #expect(Transcript(tokens: tokens).words.map(\.text) == ["Hello", "world"])
    }

    @Test func sentenceCuesSplitOnPunctuationAndPauses() {
        let transcript = Transcript(words: [
            Word(text: "Ciao.", start: 0, end: 0.5),
            Word(text: "Come", start: 0.6, end: 0.8),
            Word(text: "va", start: 0.9, end: 1.0),
            Word(text: "dopo", start: 3.0, end: 3.4),
        ])
        #expect(transcript.sentenceCues() == [
            Cue(start: 0, end: 0.5, text: "Ciao."),
            Cue(start: 0.6, end: 1.0, text: "Come va"),
            Cue(start: 3.0, end: 3.4, text: "dopo"),
        ])
    }

    @Test func srtNumbersAndFormatsCues() {
        let srt = SubtitleFile.srt([
            Cue(start: 0, end: 1.5, text: "Uno"),
            Cue(start: 3661.0425, end: 3662, text: "Due"),
        ])
        #expect(srt == "1\n00:00:00,000 --> 00:00:01,500\nUno\n\n2\n01:01:01,043 --> 01:01:02,000\nDue\n")
    }

    @Test func subtitleFileSitsNextToMediaFile() {
        #expect(SubtitleFile.url(for: URL(filePath: "/v/intervista.mov")).path == "/v/intervista.srt")
    }
}

@Suite struct ModelLocatorTests {
    let root = URL(filePath: "/AS")

    @Test func prefersUltraAnywhereOverV3() {
        let present: Set<String> = [
            "/AS/Dimmela/Models/fluidaudio/parakeet-tdt-0.6b-v3/.dimmela-downloaded",
            "/AS/Takku/Models/fluidaudio/parakeet-ultra/.takku-downloaded",
        ]
        let found = ModelLocator.standard(applicationSupport: root).candidates { present.contains($0.path) }
        #expect(found.map(\.model) == [.ultra, .v3])
        #expect(found.map(\.owner.name) == ["Takku", "Dimmela"])
    }

    @Test func ownFolderFirstAndMarkerRequired() {
        let present: Set<String> = [
            "/AS/Sottovoce/Models/fluidaudio/parakeet-ultra/.sottovoce-downloaded",
            "/AS/Takku/Models/fluidaudio/parakeet-ultra/.takku-downloaded",
            // Folder without its owner's marker: a download interrupted halfway.
            "/AS/Dimmela/Models/fluidaudio/parakeet-ultra/.takku-downloaded",
        ]
        let found = ModelLocator.standard(applicationSupport: root).candidates { present.contains($0.path) }
        #expect(found.map(\.owner.name) == ["Sottovoce", "Takku"])
    }
}
