import Foundation
import Testing
@testable import SottovoceCore

@Suite struct VocabularyTests {
    @Test func parsesTakkuFormatAndIgnoresProse() {
        let content = """
            # Vocabulary

            Lines without a dash are ignored.
            - Scaleway = scale uai, scale away | EU cloud provider
            - Sottovoce = sotto voce
            - Scaleway = duplicate ignored
            """
        let vocab = Vocabulary(fileContent: content)
        #expect(vocab.entries == [
            Vocabulary.Entry(term: "Scaleway", variants: ["scale uai", "scale away"], description: "EU cloud provider"),
            Vocabulary.Entry(term: "Sottovoce", variants: ["sotto voce"]),
        ])
    }

    @Test func replacesSingleAndMultiWordVariantsPreservingTimingsAndPunctuation() {
        let vocab = Vocabulary(fileContent: """
            - Scaleway = scale uai
            - DaVinci = da vinci
            - Parakeet = parakit
            """)
        let transcript = Transcript(words: [
            Word(text: "Usiamo", start: 0.0, end: 0.4, speaker: 1),
            Word(text: "scale", start: 0.4, end: 0.7, speaker: 1),
            Word(text: "uai,", start: 0.7, end: 1.0, speaker: 1),
            Word(text: "parakit.", start: 1.1, end: 1.5, speaker: 2),
        ])
        let fixed = vocab.applying(to: transcript)
        #expect(fixed.words == [
            Word(text: "Usiamo", start: 0.0, end: 0.4, speaker: 1),
            Word(text: "Scaleway,", start: 0.4, end: 1.0, speaker: 1),
            Word(text: "Parakeet.", start: 1.1, end: 1.5, speaker: 2),
        ])
    }

    @Test func multiWordVariantDoesNotCrossSpeakerBoundary() {
        let vocab = Vocabulary(fileContent: "- Scaleway = scale uai")
        let transcript = Transcript(words: [
            Word(text: "scale", start: 0.0, end: 0.3, speaker: 1),
            Word(text: "uai", start: 0.4, end: 0.7, speaker: 2),
        ])
        #expect(vocab.applying(to: transcript) == transcript)
    }
}

@Suite struct SpeakersTests {
    @Test func assignsSpeakersInOrderOfFirstAppearance() {
        let words = [
            Word(text: "Ciao", start: 0.2, end: 0.5),
            Word(text: "a", start: 0.5, end: 0.6),
            Word(text: "te", start: 1.2, end: 1.5),
            Word(text: "sì", start: 2.0, end: 2.2), // nearest turn within 2 s is S0
        ]
        let turns = [
            SpeakerTurn(voice: "S3", start: 0.0, end: 0.8),
            SpeakerTurn(voice: "S0", start: 1.0, end: 1.7),
        ]
        let assigned = assigningSpeakers(to: words, turns: turns)
        #expect(assigned.map(\.speaker) == [1, 1, 2, 2])
    }

    @Test func classicStyleSplitsOnSpeakerChange() {
        let transcript = Transcript(words: [
            Word(text: "Ciao", start: 0.0, end: 0.3, speaker: 1),
            Word(text: "come", start: 0.35, end: 0.6, speaker: 1),
            Word(text: "bene", start: 0.65, end: 0.9, speaker: 2),
            Word(text: "grazie", start: 0.95, end: 1.3, speaker: 2),
        ])
        let cues = ClassicStyle().cues(transcript)
        #expect(cues.map(\.text) == ["Ciao come", "bene grazie"])
    }

    @Test func shortStyleNeverCombinesTwoSpeakers() {
        let transcript = Transcript(words: [
            Word(text: "Uno", start: 0.0, end: 0.08, speaker: 1), // < 0.15 s, would merge if same speaker
            Word(text: "Due", start: 0.10, end: 0.40, speaker: 2),
            Word(text: "Tre", start: 0.45, end: 0.70, speaker: 2),
        ])
        let cues = ShortStyle(words: 3).cues(transcript)
        #expect(cues.map(\.text) == ["Uno", "Due Tre"])
    }

    @Test func commandParsesWatchSpeakersAndClassicParameters() throws {
        let cmd = try Command.parse([
            "watch", "/tmp/inbox",
            "--speakers",
            "--max-line-chars", "36",
            "--max-lines", "1",
            "--max-duration", "5.5",
            "--max-cps", "15",
        ])
        #expect(cmd == .watch(
            folder: "/tmp/inbox",
            options: .init(
                speakers: true,
                maxLineCharacters: 36,
                maxLines: 1,
                maxDuration: 5.5,
                maxCharactersPerSecond: 15
            )
        ))
        #expect(throws: Command.ParseError.missingFolder) {
            try Command.parse(["watch"])
        }
        #expect(throws: Command.ParseError.invalidValue(option: "--max-lines", value: "3", expected: "1 or 2")) {
            try Command.parse(["a.mov", "--max-lines", "3"])
        }
    }

    @Test func modelLocatorBorrowsNemotronFromSisterApps() {
        let root = URL(filePath: "/AS")
        let present: Set<String> = [
            "/AS/Takku/Models/fluidaudio/\(ModelLocator.nemotronRequiredFile)",
        ]
        let owners = ModelLocator.standard(applicationSupport: root).nemotronCandidates { present.contains($0.path) }
        #expect(owners.map(\.name) == ["Takku"])
    }

    @Test func translationURLAndCommandValidation() throws {
        #expect(SubtitleFile.url(for: URL(filePath: "/v/film.mov"), format: .srt, language: "it").path == "/v/film.it.srt")
        #expect(SubtitleFile.url(for: URL(filePath: "/v/film.mov"), format: .vtt, language: "en").path == "/v/film.en.vtt")

        let cmd = try Command.parse(["film.mov", "--translate", "IT"])
        #expect(cmd == .subtitle(mediaFiles: ["film.mov"], options: .init(translate: "it")))

        #expect(throws: Command.ParseError.invalidCombination("--translate is only supported with the classic style")) {
            try Command.parse(["film.mov", "--style", "short", "--translate", "it"])
        }
    }
}
