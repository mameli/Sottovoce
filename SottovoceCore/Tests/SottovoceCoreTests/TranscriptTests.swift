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
        #expect(!Data(srt.utf8).starts(with: [0xEF, 0xBB, 0xBF]))
    }

    @Test func vttHasHeaderDotTimestampsAndNoBOM() {
        let vtt = SubtitleFile.vtt([
            Cue(start: 0, end: 1.5, text: "Uno"),
            Cue(start: 3661.0425, end: 3662, text: "Due"),
        ])
        #expect(vtt == "WEBVTT\n\n1\n00:00:00.000 --> 00:00:01.500\nUno\n\n2\n01:01:01.043 --> 01:01:02.000\nDue\n")
        #expect(!Data(vtt.utf8).starts(with: [0xEF, 0xBB, 0xBF]))
        #expect(SubtitleFile.vtt([]) == "WEBVTT\n")
    }

    @Test func subtitleFileDropsZeroLengthAndClampsOverlaps() {
        let cues = [
            Cue(start: 0, end: 2.0, text: "Uno"),
            Cue(start: 2.0, end: 2.0, text: "Zero"),
            Cue(start: 1.5, end: 3.0, text: "Due"),
            Cue(start: 3.5, end: 4.0, text: "   "),
            Cue(start: 4.0, end: 5.0, text: "Tre"),
        ]
        let srt = SubtitleFile.render(cues, format: .srt)
        #expect(srt == "1\n00:00:00,000 --> 00:00:02,000\nUno\n\n2\n00:00:02,000 --> 00:00:03,000\nDue\n\n3\n00:00:04,000 --> 00:00:05,000\nTre\n")
    }

    @Test func subtitleFileSitsNextToMediaFileInRequestedFormat() {
        #expect(SubtitleFile.url(for: URL(filePath: "/v/intervista.mov")).path == "/v/intervista.srt")
        #expect(SubtitleFile.url(for: URL(filePath: "/v/intervista.mov"), format: .vtt).path == "/v/intervista.vtt")
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

    @Test func sileroBorrowsFromSisterAppsAndRequiresOwnMarker() {
        let present: Set<String> = [
            // Sottovoce without marker (interrupted download): skipped.
            "/AS/Sottovoce/Models/fluidaudio/\(ModelLocator.sileroRequiredFile)",
            // Takku with compiled model: usable.
            "/AS/Takku/Models/fluidaudio/\(ModelLocator.sileroRequiredFile)",
        ]
        let owners = ModelLocator.standard(applicationSupport: root).sileroCandidates { present.contains($0.path) }
        #expect(owners.map(\.name) == ["Takku"])
    }
}

@Suite struct SpeechDetectionTests {
    @Test func silenceProducesNoRanges() {
        let probabilities = Array(repeating: Float(0.05), count: 40)
        let ranges = SpeechDetection.speechRanges(probabilities: probabilities, totalSamples: 40 * 4096)
        #expect(ranges.isEmpty)
    }

    @Test func mergesShortPausesAndSplitsLongSilence() {
        // 1 frame = 4096 samples = 0.256 s.
        // Speech at frames 10..11, 2-frame pause (~0.5 s < 2 s), speech at frame 14 -> merged.
        // Then 15 frames of silence (~3.8 s >= 2 s), then speech at frame 30 -> separate range.
        var probabilities = Array(repeating: Float(0.0), count: 40)
        probabilities[10] = 0.8
        probabilities[11] = 0.7
        probabilities[14] = 0.6
        probabilities[30] = 0.9
        let total = 40 * 4096
        let ranges = SpeechDetection.speechRanges(probabilities: probabilities, totalSamples: total)
        #expect(ranges.count == 2)
        // First range covers frames 10..14 with 0.25 s (4000 samples) padding on each side.
        #expect(ranges[0].samples == (10 * 4096 - 4000)..<(15 * 4096 + 4000))
        #expect(abs(ranges[0].speechDuration - 3 * 0.256) < 1e-6)
        // Second range covers frame 30 with 0.25 s padding.
        #expect(ranges[1].samples == (30 * 4096 - 4000)..<(31 * 4096 + 4000))
        #expect(abs(ranges[1].speechDuration - 0.256) < 1e-6)
    }

    @Test func offsetTokensShiftsAndClampsToRangeEnd() {
        let tokens = [
            TimedToken(text: " Ciao", start: 0.1, end: 0.4),
            TimedToken(text: "!", start: 0.4, end: 1.2), // beyond range end due to zero-padding
        ]
        let shifted = SpeechDetection.offsetTokens(tokens, by: 10.0, clampedTo: 10.8)
        #expect(shifted == [
            TimedToken(text: " Ciao", start: 10.1, end: 10.4),
            TimedToken(text: "!", start: 10.4, end: 10.8),
        ])
    }

    @Test func hallucinationFilterDropsBriefStockPhrasesOnly() {
        let grazie = [Word(text: "Grazie.", start: 0, end: 0.5)]
        #expect(SpeechDetection.isLikelyHallucination(grazie, speechDuration: 0.5))
        #expect(!SpeechDetection.isLikelyHallucination(grazie, speechDuration: 4.0))
        let real = [Word(text: "Ciao", start: 0, end: 0.3), Word(text: "amici.", start: 0.3, end: 0.7)]
        #expect(!SpeechDetection.isLikelyHallucination(real, speechDuration: 0.7))
    }
}
